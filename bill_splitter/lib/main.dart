import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http; // We added this to make web requests

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
  String _scanResults = "";

  final String mindeeApiKey = "md_TAYNqK4USYKl8J5pVYmA7wZ4Jtb63Asm1CWMR-Ctfk4";

  // This function picks the image, then immediately starts scanning it
  Future<void> _pickAndScanImage() async {
    final XFile? selectedImage = await _picker.pickImage(source: ImageSource.gallery);

    if (selectedImage != null) {
      setState(() {
        _imageFile = selectedImage;
        _isScanning = true;
        _scanResults = "Analyzing receipt with AI...";
      });

      await _scanReceiptWithMindee(selectedImage);
    }
  }

  // This function talks to the Mindee API
  Future<void> _scanReceiptWithMindee(XFile image) async {
    try {
      // Mindee's endpoint for expense receipts
      final url = Uri.parse('https://proxy.corsfix.com/?https://api.mindee.net/v1/products/mindee/expense_receipts/v5.3/predict');
      var request = http.MultipartRequest('POST', url);

      // Securely pass your API key to Mindee
      request.headers['Authorization'] = 'Token $mindeeApiKey';

      // Convert the web image file into bytes for uploading
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'document',
        bytes,
        filename: image.name,
      ));

      // Send the request and wait for the AI to read it
      final response = await request.send();
      final responseData = await response.stream.bytesToString();


      if (response.statusCode == 201 || response.statusCode == 200) {
         final json = jsonDecode(responseData);
        // Dig into the JSON data Mindee sent back to find the total and supplier
        final document = json['document']['inference']['prediction'];
        final total = document['total_amount']['value'];
        final supplier = document['supplier_name']['value'] ?? "Unknown Store";

        setState(() {
          _scanResults = "Store: $supplier\nTotal Amount: \$$total";
          _isScanning = false;
        });
      } else {
        setState(() {
          _scanResults = "Failed to scan. Is your API key correct?";
          _isScanning = false;
        });
      }
    } catch (e) {
      setState(() {
        _scanResults = "Store: $supplier\nTotal Amount: \$$total";
        _isScanning = false;
      });
    } else {
      setState((){
        _scanResults = "App Error:\n$e";
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Show the file name if uploaded
            if (_imageFile != null) ...[
              const Icon(Icons.receipt_long, color: Colors.teal, size: 60),
              const SizedBox(height: 10),
              Text("File: ${_imageFile!.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
            ],

            // Show a loading spinner while scanning, or show the results when done
            if (_isScanning)
              const CircularProgressIndicator()
            else if (_scanResults.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal),
                ),
                child: Text(
                  _scanResults,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 30),

            // The main upload button
            ElevatedButton.icon(
              // Disable the button while scanning so the user can't spam it
              onPressed: _isScanning ? null : _pickAndScanImage,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Upload & Scan Receipt'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}