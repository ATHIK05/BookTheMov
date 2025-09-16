import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;

class UserDetailsPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserDetailsPage({Key? key, required this.userData}) : super(key: key);

  @override
  _UserDetailsPageState createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool isLoading = false;
  PdfController? _pdfController;

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userData = widget.userData;
    final String name = userData['name'] ?? 'Unknown';
    final String email = userData['email'] ?? 'Unknown';
    final String mobile = userData['mobile'] ?? 'Unknown';
    final String gstNumber = userData['gst'] ?? 'Not Provided';
    final bool isConfirmed = userData['status'] == 'yes';
    final String? aadharUrl = userData['aadhar'];
    final String? panBase64 = userData['pan'];
    final String? aadharFileName = userData['aadharFileName'];

    return Scaffold(
      appBar: AppBar(
        title: Text('Theatre Owner Details',style: TextStyle(color: Colors.white,fontWeight: FontWeight.bold),),
        backgroundColor: Colors.red.shade800,
        elevation: 0,
        actions: [
          if (!isConfirmed)
            IconButton(
              icon: Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => _approveUser(userData['userId']),
              tooltip: 'Approve User',
            ),
          if (!isConfirmed)
            IconButton(
              icon: Icon(Icons.cancel, color: Colors.red),
              onPressed: () => _showRejectionDialog(userData['userId']),
              tooltip: 'Reject User',
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[50]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red[400]!, Colors.red[600]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  email,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  mobile,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isConfirmed)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'VERIFIED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.receipt, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'GST: $gstNumber',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),

              // Documents Section
              Text(
                'Documents',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 16),

              // Aadhaar Document
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Aadhaar Document',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      if (aadharUrl != null) ...[
                        // Modern Aadhaar Document Display
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.picture_as_pdf, color: Colors.red, size: 48),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      aadharFileName ?? 'Aadhaar Document',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Tap to view the full document',
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AadhaarPdfFullScreenPage(
                                        pdfUrl: aadharUrl,
                                        fileName: aadharFileName ?? 'Aadhaar Document',
                                      ),
                                    ),
                                  );
                                },
                                icon: Icon(Icons.open_in_new, color: Colors.white),
                                label: Text('View', style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                        if (aadharFileName != null)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AadhaarPdfFullScreenPage(pdfUrl: aadharUrl, fileName: aadharFileName),
                                ),
                              );
                            },
                            child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.description, color: Colors.grey[600]),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      aadharFileName,
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.open_in_new, color: Colors.red.shade600, size: 20),
                                ],
                              ),
                            ),
                          ),
                      ] else ...[
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Aadhaar document not uploaded',
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),

              // PAN Document
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.credit_card, color: Colors.blue, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'PAN Card',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      if (panBase64 != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            base64Decode(panBase64),
                            fit: BoxFit.cover,
                            height: 200,
                            width: double.infinity,
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'PAN card not uploaded',
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),

              // Action Buttons (only for unconfirmed users)
              if (!isConfirmed) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : () => _approveUser(userData['userId']),
                        icon: isLoading
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(Icons.check_circle, color: Colors.white),
                        label: Text(
                          isLoading ? 'Processing...' : 'Approve User',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : () => _showRejectionDialog(userData['userId']),
                        icon: Icon(Icons.cancel, color: Colors.white),
                        label: Text(
                          'Reject User',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveUser(String userID) async {
    setState(() => isLoading = true);
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await _firestore.collection('movie_users').doc(currentUser.uid).get();
        final adminData = userDoc.data();
        if (adminData != null) {
          final customerDoc = await _firestore.collection('movie_users').doc(userID).get();
          final customerData = customerDoc.data();
          String? razorpayId = customerData?['razorpayAccountId'];
          
          if (razorpayId == null || !razorpayId.toString().trim().startsWith('acc_')) {
            final TextEditingController rzpController = TextEditingController();
            bool valid = false;
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) {
                return StatefulBuilder(
                  builder: (context, setState) {
                    return AlertDialog(
                      title: Text('Enter Razorpay Account ID'),
                      content: TextField(
                        controller: rzpController,
                        decoration: InputDecoration(
                          labelText: 'Razorpay Account ID (acc_...)',
                          hintText: 'acc_1234567890abcdef',
                          errorText: valid || rzpController.text.isEmpty || rzpController.text.startsWith('acc_') ? null : 'Must start with acc_',
                        ),
                        onChanged: (val) {
                          setState(() {
                            valid = val.trim().startsWith('acc_');
                          });
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (rzpController.text.trim().startsWith('acc_')) {
                              await _firestore.collection('movie_users').doc(userID).update({
                                'razorpayAccountId': rzpController.text.trim(),
                              });
                              Navigator.pop(ctx);
                            }
                          },
                          child: Text('Save'),
                        ),
                      ],
                    );
                  },
                );
              },
            );
            final updatedDoc = await _firestore.collection('movie_users').doc(userID).get();
            razorpayId = updatedDoc.data()?['razorpayAccountId'];
          }
          
          if (razorpayId != null && razorpayId.toString().trim().startsWith('acc_')) {
            await _firestore.collection('movie_users').doc(userID).update({
              'status': 'yes',
              'verifiedby': {
                'id': currentUser.uid,
                'name': adminData['name'],
                'mobile': adminData['mobile'],
              }
            });
            Fluttertoast.showToast(msg: 'Theatre owner approved successfully!');
            Navigator.pop(context);
          } else {
            Fluttertoast.showToast(msg: 'Theatre owner approval requires a valid Razorpay Account ID for receiving payments.');
          }
        } else {
          Fluttertoast.showToast(msg: 'Admin verification data not found');
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error approving theatre owner: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _showRejectionDialog(String userID) async {
    final TextEditingController reasonController = TextEditingController();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cancel, color: Colors.red),
              SizedBox(width: 8),
              Text('Rejection Reason'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please provide a reason for rejecting this user:'),
              SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter rejection reason...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.trim().isNotEmpty) {
                  await _rejectUser(userID, reasonController.text.trim());
                  Navigator.pop(ctx);
                } else {
                  Fluttertoast.showToast(msg: 'Please provide a rejection reason');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Reject', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rejectUser(String userID, String reason) async {
    setState(() => isLoading = true);
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await _firestore.collection('movie_users').doc(currentUser.uid).get();
        final userData = userDoc.data();

        if (userData != null) {
          await _firestore.collection('movie_users').doc(userID).update({
            'status': 'Disagree',
            'rejectionReason': reason,
            'verifiedby': {
              'id': currentUser.uid,
              'name': userData['name'],
              'mobile': userData['mobile'],
            }
          });

          Fluttertoast.showToast(msg: 'Theatre owner application rejected!');
          Navigator.pop(context);
        } else {
          Fluttertoast.showToast(msg: 'Theatre owner data not found');
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error rejecting theatre owner: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }
}

Future<PdfController> _getPdfController(String url) async {
  final document = PdfDocument.openData((await http.get(Uri.parse(url))).bodyBytes);
  return PdfController(document: document);
}

// Aadhaar Document Preview Widget
class AadhaarPdfPreview extends StatelessWidget {
  final String url;
  const AadhaarPdfPreview({required this.url});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PdfDocument>(
      future: _loadPdf(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return Center(child: Icon(Icons.picture_as_pdf, color: Colors.red, size: 64));
        }
        return SizedBox(
          height: 180,
          child: PdfView(
            controller: PdfController(document: Future.value(snapshot.data!)),
            builders: PdfViewBuilders<DefaultBuilderOptions>(
              options: DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => Center(child: CircularProgressIndicator()),
              pageLoaderBuilder: (_) => Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) => Center(child: Text('Failed to load PDF')),
            ),
            scrollDirection: Axis.horizontal,
          ),
        );
      },
    );
  }
  static Future<PdfDocument> _loadPdf(String url) async {
    final response = await http.get(Uri.parse(url));
    return PdfDocument.openData(response.bodyBytes);
  }
}

class AadhaarPdfFullScreenPage extends StatefulWidget {
  final String pdfUrl;
  final String fileName;
  const AadhaarPdfFullScreenPage({required this.pdfUrl, required this.fileName});
  @override
  State<AadhaarPdfFullScreenPage> createState() => _AadhaarPdfFullScreenPageState();
}

class _AadhaarPdfFullScreenPageState extends State<AadhaarPdfFullScreenPage> {
  PdfController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    final document = await AadhaarPdfPreview._loadPdf(widget.pdfUrl);
    setState(() {
      _controller = PdfController(document: Future.value(document));
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: Colors.teal,
      ),
      body: _loading || _controller == null
          ? Center(child: CircularProgressIndicator())
          : PdfView(
              controller: _controller!,
              scrollDirection: Axis.vertical,
              builders: PdfViewBuilders<DefaultBuilderOptions>(
                options: DefaultBuilderOptions(),
                documentLoaderBuilder: (_) => Center(child: CircularProgressIndicator()),
                pageLoaderBuilder: (_) => Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error) => Center(child: Text('Failed to load PDF')),
              ),
            ),
    );
  }
}
