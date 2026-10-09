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
  String _receiptCurrency = '\$'; 
  
  // VARIABLE TO HOLD THE USER's TOTAL
  double _selectedTotal = 0.0;

  // FUNCTION TO CALCULATE TOTAL
  void _calculateTotal() {
    double tempTotal = 0.0;
    for (var item in _parsedItems) {
      if (item.isSelected) {
        tempTotal += item.price;
      }
    }
    setState(() {
      _selectedTotal = tempTotal;
    });
  }

  Future<void> _pickAndScanImage() async {
    final XFile? selectedImage = await _picker.pickImage(source: ImageSource.gallery);

    if (selectedImage != null) {
      setState(() {
        _imageFile = selectedImage;
        _isScanning = true;
        _errorMessage = "";
        _parsedItems.clear();
        _selectedTotal = 0.0; // Reset total on new scan
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
        
        String tempCurrency = '\$'; 
        String lowerText = parsedText.toLowerCase();
        
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

        List<ReceiptItem> tempItems = [];
        List<String> lines = parsedText.split('\n');
        
        RegExp priceRegex = RegExp(r'^(.*?)\s+[\$£€]?\s*(\d+\.\d{2})\s*$');
        
        for (int i = 0; i < lines.length; i++) {
          String currentLine = lines[i].trim();
          Match? match = priceRegex.firstMatch(currentLine);
          
          if (match != null) {
            String itemName = match.group(1)?.trim() ?? 'Unknown Item';
            double itemPrice = double.tryParse(match.group(2) ?? '0.0') ?? 0.0;
            
            String lowerName = itemName.toLowerCase();
            
            if (itemPrice <= 0 ||
                lowerName.contains('total') || 
                lowerName.contains('tax') || 
                lowerName.contains('mpesa') || 
                lowerName.contains('cash') ||
                lowerName.contains('change') ||
                lowerName.contains('pay')) {
              continue; 
            }

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
          _receiptCurrency = tempCurrency; 
          
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
                        subtitle: Text('$_receiptCurrency${item.price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.teal)),
                        value: item.isSelected,
                        activeColor: Colors.teal,
                        onChanged: (bool? value) {
                          setState(() {
                            item.isSelected = value ?? false;
                            // RECALCULATE TOTAL WHEN TAPPED
                            _calculateTotal(); 
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
      // BOTTOM BAR TO SHOW TOTAL
      bottomNavigationBar: _parsedItems.isNotEmpty 
        ? SafeArea(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  )
                ]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total: $_receiptCurrency${_selectedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    // Button is disabled if total is 0
                    onPressed: _selectedTotal > 0 ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaymentScreen(
                            totalAmount: _selectedTotal,
                            currency: _receiptCurrency,
                          ),
                        ),
                      );
                    } : null, 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Confirm Share', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          )
        : null, 
    );
  }
}

// ---------------------------------------------------
// --- THE ONAFRIQ EAST AFRICA PAYMENT SCREEN ---
// ---------------------------------------------------
class PaymentScreen extends StatefulWidget {
  final double totalAmount;
  final String currency;

  const PaymentScreen({super.key, required this.totalAmount, required this.currency});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isProcessing = false;
  String _paymentStatus = "";
  
  String _selectedCountry = 'Kenya (M-Pesa / Airtel)';

  final List<String> _africanCountries = [
    'Kenya (M-Pesa / Airtel)',
    'Uganda (MTN / Airtel)',
    'Tanzania (Vodacom / Tigo / Airtel)',
    'Rwanda (MTN / Airtel)',
    'DRC (Orange / M-Pesa / Airtel)',
    'Ethiopia (Telebirr / M-Pesa)',
    'Burundi (EcoCash / Lumicash)',
    'South Sudan (m-GURUSH)',
    'Somalia (EVC Plus)'
    'Nigeria(Opay/Paga/MoMo)',
    'Ghana(MTN MoMo/Telecel Cash)',
    'Côte d\'Ivoire (Orange/ MTN)',
    'Senegal (Wave / Orange Money)'
    'Cameroon (MTN / Orange Money)',
    'South Africa (Vodapay / MTN)',
    'Zambia (Airtel / MTN)',
    'Zimbabwe (EcoCash)',
    'Egypt (Vodafone Cash)'
  ];

  void _simulateOnafriqPayment() {
    if (_phoneController.text.isEmpty) {
      setState(() {
        _paymentStatus = "Please enter your mobile money number.";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _paymentStatus = "Connecting to Onafriq Gateway...\nSending payment prompt to ${_phoneController.text} via $_selectedCountry.";
    });

    Future.delayed(const Duration(seconds: 4), () {
      setState(() {
        _isProcessing = false;
        _paymentStatus = "Payment of ${widget.currency}${widget.totalAmount.toStringAsFixed(2)} Successful! ✅\nProcessed securely across borders.";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your Total Share',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.currency}${widget.totalAmount.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            const SizedBox(height: 40),
            
            DropdownButtonFormField<String>(
              value: _selectedCountry,
              decoration: const InputDecoration(
                labelText: 'Select Country & Provider',
                prefixIcon: Icon(Icons.public),
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: _africanCountries.map((String country) {
                return DropdownMenuItem<String>(
                  value: country,
                  child: Text(country, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedCountry = newValue!;
                });
              },
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Money Number',
                hintText: 'e.g., 0712345678',
                prefixIcon: Icon(Icons.phone_android),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            
            if (_paymentStatus.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _paymentStatus.contains('Successful') ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _paymentStatus.contains('Successful') ? Colors.green : Colors.blue,
                  ),
                ),
                child: Text(
                  _paymentStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    height: 1.4,
                    color: _paymentStatus.contains('Successful') ? Colors.green.shade700 : Colors.blue.shade700,
                  ),
                ),
              ),
              
            ElevatedButton(
              onPressed: _isProcessing ? null : _simulateOnafriqPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700, 
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isProcessing 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Process Mobile Money Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            
            const SizedBox(height: 16),
            const Text(
              'Powered by Onafriq Pan-African Gateway',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          ],
        ),
      ),
    );
  }
}