import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// 1. DATA MODEL
class ReceiptItem {
  final String name;
  final double price;
  bool isSelected;

  ReceiptItem({required this.name, required this.price, this.isSelected = false});
}

void main() {
  runApp(const BillSplitterApp());
}

class BillSplitterApp extends StatelessWidget {
  const BillSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bill Splitter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  bool _isScanning = false;
  String _errorMessage = "";
  
  // 2. STATE VARIABLES
  List<ReceiptItem> _parsedItems = [];
  String _receiptCurrency = '\$'; // Default currency

  Future<void> _pickAndScanImage() async {
    final XFile? selectedImage = await _picker.pickImage(source: ImageSource.gallery);

    if (selectedImage != null) {
      setState(() {
        _imageFile = selectedImage;
        _isScanning = true;
        _errorMessage = "";
        _parsedItems.clear();
      });

      await _scanReceipt(selectedImage);
    }
  }

  Future<void> _scanReceipt(XFile image) async {
    try {
      final url = Uri.parse('https://api.ocr.space/parse/image');
      var request = http.MultipartRequest('POST', url);

      request.fields['apikey'] = 'helloworld';
      request.fields['isTable'] = 'true'; 

      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'file', 
        bytes,
        filename: image.name,
      ));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final json = jsonDecode(responseData);
        
        if (json['IsErroredOnProcessing'] == true) {
           setState(() {
            _errorMessage = "OCR Error: ${json['ErrorMessage']}";
            _isScanning = false;
          });
          return;
        }

        final parsedText = json['ParsedResults'][0]['ParsedText'];
        
        // --- NEW: CURRENCY DETECTOR ---
        String tempCurrency = '\$'; // Default to dollar
        String lowerText = parsedText.toLowerCase();
        
        // Scan the whole receipt text for specific currency markers
        if (lowerText.contains('ksh') || lowerText.contains('kes')) {
          tempCurrency = 'Ksh ';
        } else if (lowerText.contains('ugx')) {
          tempCurrency = 'UGX ';
        } else if (lowerText.contains('tzs')) {
          tempCurrency = 'TZS ';
        } else if (parsedText.contains('€')) {
          tempCurrency = '€';
        } else if (parsedText.contains('£')) {
          tempCurrency = '£';
        }

        // 3. THE SMART PARSER
        List<ReceiptItem> tempItems = [];
        List<String> lines = parsedText.split('\n');
        
        // Allows for optional currency symbols at the start of the price
        RegExp priceRegex = RegExp(r'^(.*?)\s+[\$£€]?\s*(\d+\.\d{2})\s*$');
        
        for (int i = 0; i < lines.length; i++) {
          String currentLine = lines[i].trim();
          Match? match = priceRegex.firstMatch(currentLine);
          
          if (match != null) {
            String itemName = match.group(1)?.trim() ?? 'Unknown Item';
            double itemPrice = double.tryParse(match.group(2) ?? '0.0') ?? 0.0;
            
            String lowerName = itemName.toLowerCase();
            
            // FILTER 1: Ignore zero-cost items, payments, and totals
            if (itemPrice <= 0 ||
                lowerName.contains('total') || 
                lowerName.contains('tax') || 
                lowerName.contains('mpesa') || 
                lowerName.contains('cash') ||
                lowerName.contains('change') ||
                lowerName.contains('pay')) {
              continue; 
            }

            // FILTER 2: Fix the names
            if (lowerName.contains(' pc') || lowerName.contains(' kg') || RegExp(r'^\d{4,}').hasMatch(itemName)) {
                if (i > 0) {
                    String previousLine = lines[i-1].trim();
                    if (previousLine.isNotEmpty && !priceRegex.hasMatch(previousLine)) {
                        itemName = previousLine;
                    } else {
                        itemName = itemName.replaceAll(RegExp(r'^\d{4,}\s*'), ''); 
                        itemName = itemName.replaceAll(RegExp(r'\d+\.\d{2,3}\s*(PC|KG|pc|kg)', caseSensitive: false), '').trim();
                    }
                }
            }
            
            tempItems.add(ReceiptItem(name: itemName, price: itemPrice));
          }
        }

        setState(() {
          _parsedItems = tempItems;
          _receiptCurrency = tempCurrency; // Save the detected currency to the state
          
          if (_parsedItems.isEmpty) {
            _errorMessage = "Couldn't find any prices on this receipt. Try a clearer photo.";
          }
          _isScanning = false;
        });

      } else {
        setState(() {
          _errorMessage = "Server Error ${response.statusCode}";
          _isScanning = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "App Error:\n$e";
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split the Bill'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _pickAndScanImage,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Upload & Scan Receipt'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            
            const SizedBox(height: 20),

            if (_isScanning)
              const CircularProgressIndicator(),
            
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),

            // 4. THE UI
            if (_parsedItems.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _parsedItems.length,
                  itemBuilder: (context, index) {
                    final item = _parsedItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: CheckboxListTile(
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        // --- NEW: DISPLAYS THE DYNAMIC CURRENCY ---
                        subtitle: Text('$_receiptCurrency${item.price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.teal)),
                        value: item.isSelected,
                        activeColor: Colors.teal,
                        onChanged: (bool? value) {
                          setState(() {
                            item.isSelected = value ?? false;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}