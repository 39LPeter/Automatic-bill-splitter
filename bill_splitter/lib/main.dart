import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// 1. DATA MODEL: This defines what a single line on the receipt looks like in code
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
  
  // 2. THE LIST: This will hold all the extracted items
  List<ReceiptItem> _parsedItems = [];

  Future<void> _pickAndScanImage() async {
    final XFile? selectedImage = await _picker.pickImage(source: ImageSource.gallery);

    if (selectedImage != null) {
      setState(() {
        _imageFile = selectedImage;
        _isScanning = true;
        _errorMessage = "";
        _parsedItems.clear(); // Clear old items when a new receipt is uploaded
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

        // 3. THE PARSER: Hunt for prices using Regex
        List<ReceiptItem> tempItems = [];
        
        // This Regex looks for text, optional spaces/currency symbols, and a decimal number at the end
        RegExp priceRegex = RegExp(r'^(.*?)\s+[\$£€]?\s*(\d+\.\d{2})\s*$');
        
        for (String line in parsedText.split('\n')) {
          Match? match = priceRegex.firstMatch(line.trim());
          
          if (match != null) {
            String itemName = match.group(1)?.trim() ?? 'Unknown Item';
            double itemPrice = double.tryParse(match.group(2) ?? '0.0') ?? 0.0;
            
            // Basic filter: ignore the subtotal/total lines for now so they don't look like food
            if (!itemName.toLowerCase().contains('total') && !itemName.toLowerCase().contains('tax')) {
              tempItems.add(ReceiptItem(name: itemName, price: itemPrice));
            }
          }
        }

        setState(() {
          _parsedItems = tempItems;
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
            
            // The Upload Button
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

            // 4. THE UI: A clickable list of items
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
                        subtitle: Text('\$${item.price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.teal)),
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