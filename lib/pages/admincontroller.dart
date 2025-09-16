import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'login.dart';
import 'AdminSupportTicketsPage.dart';
import 'UserDetailsPage.dart';

class AdminControllersPage extends StatefulWidget {
  const AdminControllersPage({super.key});

  @override
  _AdminControllersPageState createState() => _AdminControllersPageState();
}

class _AdminControllersPageState extends State<AdminControllersPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> notConfirmedUsers = [];
  List<Map<String, dynamic>> confirmedUsers = [];
  bool isLoading = true;

  // 1. Add state for pending/verified turfs
  List<Map<String, dynamic>> pendingTheatres = [];
  List<Map<String, dynamic>> verifiedTheatres = [];
  bool isLoadingTheatres = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    fetchUserData();
    fetchTheatreData();
  }

  Future<void> fetchUserData() async {
    setState(() {
      isLoading = true;
    });

    QuerySnapshot usersSnapshot = await _firestore.collection('movie_users').get();

    List<Map<String, dynamic>> tempNotConfirmed = [];
    List<Map<String, dynamic>> tempConfirmed = [];

    for (var userDoc in usersSnapshot.docs) {
      var userData = userDoc.data() as Map<String, dynamic>;
      String userId = userDoc.id;

      var documentData = await _fetchDocumentData(userId);

      if (documentData != null) {
        userData['userId'] = userId;
        userData['gst'] = documentData['gst'] ?? 'Not Provided';
        userData['aadhar'] = documentData['aadhar'];
        userData['pan'] = documentData['pan'];
        userData['aadharFileName'] = documentData['aadharFileName'];
      }

      if (userData['status'] == 'Not Confirmed') {
        tempNotConfirmed.add(userData);
      } else if (userData['status'] == 'yes') {
        tempConfirmed.add(userData);
      }
    }

    setState(() {
      notConfirmedUsers = tempNotConfirmed;
      confirmedUsers = tempConfirmed;
      isLoading = false;
    });
  }

  Future<Map<String, dynamic>?> _fetchDocumentData(String userId) async {
    DocumentSnapshot documentSnapshot =
    await _firestore.collection('documents').doc(userId).get();

    if (documentSnapshot.exists) {
      return documentSnapshot.data() as Map<String, dynamic>;
    }
    return null;
  }

  // 2. Fetch theatres from Firestore
  Future<void> fetchTheatreData() async {
    setState(() { isLoadingTheatres = true; });
    final pendingSnapshot = await _firestore.collection('movie_theatres').where('theatre_status', isEqualTo: 'Not Verified').get();
    final verifiedSnapshot = await _firestore.collection('movie_theatres').where('theatre_status', isEqualTo: 'Verified').get();
    setState(() {
      pendingTheatres = pendingSnapshot.docs.map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id}).toList();
      verifiedTheatres = verifiedSnapshot.docs.map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id}).toList();
      isLoadingTheatres = false;
    });
  }

  Widget _buildUserList(List<Map<String, dynamic>> users) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 20),
            Text(
              'Loading Users...',
              style: TextStyle(fontSize: 18, color: Colors.teal[700], fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 80, color: Colors.blueAccent),
            SizedBox(height: 20),
            Text(
              'No users found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            SizedBox(height: 10),
            Text(
              'Please try again later or refresh.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    } else {
      return ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          var userData = users[index];
          String name = userData['name'] ?? 'Unknown';
          String email = userData['email'] ?? 'Unknown';
          String mobile = userData['mobile'] ?? 'Unknown';
          String gstNumber = userData['gst'] ?? 'Not Provided';
          bool isConfirmed = userData['status'] == 'yes';

          return Card(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailsPage(userData: userData),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: isConfirmed 
                        ? [Colors.green[50]!, Colors.green[100]!]
                        : [Colors.orange[50]!, Colors.orange[100]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: isConfirmed ? Colors.green : Colors.orange,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        isConfirmed ? Icons.check_circle : Icons.pending,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 18, 
                                    color: Colors.black87
                                  ),
                                ),
                              ),
                              if (isConfirmed)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'VERIFIED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                          SizedBox(height: 2),
                          Text(
                            mobile,
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'GST: $gstNumber',
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
  }

  // 3. Build theatre list
  Widget _buildTheatreList(List<Map<String, dynamic>> theatres, {required bool pending}) {
    if (isLoadingTheatres) {
      return Center(child: CircularProgressIndicator(color: Colors.red));
    }
    if (theatres.isEmpty) {
      return Center(child: Text(pending ? 'No pending theatres.' : 'No verified theatres.', style: TextStyle(fontSize: 18, color: Colors.grey[700])));
    }
    return ListView.builder(
      itemCount: theatres.length,
      itemBuilder: (context, idx) {
        final theatre = theatres[idx];
        return Card(
          margin: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: theatre['imageUrl'] != null && theatre['imageUrl'].toString().isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(theatre['imageUrl'], width: 60, height: 60, fit: BoxFit.cover),
                  )
                : Container(width: 60, height: 60, color: Colors.red.shade50, child: Icon(Icons.movie, color: Colors.red)),
            title: Text(theatre['name'] ?? 'Unknown Theatre', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('movie_users').doc(theatre['ownerId']).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text('Loading owner info...', style: TextStyle(fontSize: 12, color: Colors.grey[600]));
                }
                if (snapshot.hasData && snapshot.data!.exists) {
                  final ownerData = snapshot.data!.data() as Map<String, dynamic>;
                  final ownerName = ownerData['name'] ?? 'Unknown Owner';
                  final ownerEmail = ownerData['email'] ?? 'No email';
                  return Text(
                    'Owner: $ownerName\nEmail: $ownerEmail\nLocation: ${theatre['location'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  );
                } else {
                  return Text(
                    'Owner: Unknown\nLocation: ${theatre['location'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  );
                }
              },
            ),
            trailing: pending
                ? ElevatedButton(
                    onPressed: () => _showTheatreDetailsDialog(theatre),
                    child: Text('Review',style: TextStyle(color: Colors.white),),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  )
                : Icon(Icons.check_circle, color: Colors.green),
          ),
        );
      },
    );
  }

  // 4. Show theatre details dialog
  void _showTheatreDetailsDialog(Map<String, dynamic> theatre) async {
    // Fetch owner details
    Map<String, dynamic>? ownerData;
    if (theatre['ownerId'] != null) {
      final ownerDoc = await _firestore.collection('movie_users').doc(theatre['ownerId']).get();
      if (ownerDoc.exists) ownerData = ownerDoc.data() as Map<String, dynamic>?;
    }
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(theatre['name'] ?? 'Unknown Theatre', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.red.shade900)),
                SizedBox(height: 10),
                if (theatre['imageUrl'] != null && theatre['imageUrl'].toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(theatre['imageUrl'], height: 160, width: double.infinity, fit: BoxFit.cover),
                  ),
                SizedBox(height: 10),
                Text('Owner Info:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (ownerData != null) ...[
                  Text('Name: ${ownerData['name'] ?? ''}'),
                  Text('Email: ${ownerData['email'] ?? ''}'),
                  Text('Phone: ${ownerData['mobile'] ?? ''}'),
                  Text('GST: ${ownerData['gst'] ?? 'N/A'}'),
                ],
                SizedBox(height: 8),
                Text('Location: ${theatre['location'] ?? 'N/A'}'),
                SizedBox(height: 8),
                Text('Description: ${theatre['description'] ?? 'No description provided'}'),
                SizedBox(height: 8),
                Text('Theatre Facilities: ${(theatre['facilities'] as List?)?.join(", ") ?? 'No facilities listed'}'),
                SizedBox(height: 8),
                if (theatre['theatreImages'] != null && (theatre['theatreImages'] as List).isNotEmpty) ...[
                  Text('Gallery:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  SizedBox(
                    height: 80,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: (theatre['theatreImages'] as List).map<Widget>((img) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(img, width: 80, height: 80, fit: BoxFit.cover),
                        ),
                      )).toList(),
                    ),
                  ),
                ],
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _approveTheatre(theatre['id']),
                      icon: Icon(Icons.check, color: Colors.white),
                      label: Text('Approve',style: TextStyle(color: Colors.white),),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showTheatreRejectionDialog(theatre['id']),
                      icon: Icon(Icons.cancel, color: Colors.white),
                      label: Text('Disapprove',style: TextStyle(color: Colors.white),),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 5. Approve theatre
  Future<void> _approveTheatre(String theatreId) async {
    try {
      setState(() { isLoadingTheatres = true; });
      
      await _firestore.collection('movie_theatres').doc(theatreId).update({
        'theatre_status': 'Verified',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': _auth.currentUser?.uid ?? 'admin',
      });
      
      await fetchTheatreData();
      Fluttertoast.showToast(
        msg: 'Theatre approved successfully! Now visible to users.',
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
      Navigator.pop(context);
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Error approving theatre: ${e.toString()}',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() { isLoadingTheatres = false; });
    }
  }

  // 6. Disapprove theatre
  void _showTheatreRejectionDialog(String theatreId) {
    final TextEditingController reasonController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Disapprove Theatre', style: TextStyle(color: Colors.red.shade700)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Please provide a clear reason for disapproval. This will help the theatre owner understand what needs to be changed.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Enter detailed reason for disapproval...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please provide a reason for disapproval';
                    }
                    if (value.trim().length < 10) {
                      return 'Please provide a more detailed reason (at least 10 characters)';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    setState(() { isLoadingTheatres = true; });
                    
                    await _firestore.collection('movie_theatres').doc(theatreId).update({
                      'theatre_status': 'Disapproved',
                      'rejectionReason': reasonController.text.trim(),
                      'rejectedAt': FieldValue.serverTimestamp(),
                      'rejectedBy': _auth.currentUser?.uid ?? 'admin',
                    });
                    
                    await fetchTheatreData();
                    Fluttertoast.showToast(
                      msg: 'Theatre disapproved. Owner will be notified with the reason.',
                      backgroundColor: Colors.orange,
                      textColor: Colors.white,
                    );
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  } catch (e) {
                    Fluttertoast.showToast(
                      msg: 'Error disapproving theatre: ${e.toString()}',
                      backgroundColor: Colors.red,
                      textColor: Colors.white,
                    );
                  } finally {
                    setState(() { isLoadingTheatres = false; });
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Disapprove', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showUserDetails(Map<String, dynamic> userData) {
    String? aadharBase64 = userData['aadhar'];
    String? panBase64 = userData['pan'];
    final String userID = userData['userId'];

    Widget aadharWidget = aadharBase64 != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aadhaar Document:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
              ),
              SizedBox(height: 8),
              if (userData['aadharFileName'] != null)
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          userData['aadharFileName'],
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.picture_as_pdf, color: Colors.white, size: 48),
                        SizedBox(height: 8),
                        Text(
                          'PDF Document',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )
        : Text(
            'Aadhaar not available',
            style: TextStyle(color: Colors.teal[300], fontStyle: FontStyle.italic),
          );

    Widget panImageWidget = panBase64 != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PAN Card:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
              ),
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(panBase64),
                  fit: BoxFit.cover,
                  height: 150,
                  width: double.infinity,
                ),
              ),
            ],
          )
        : Text(
            'PAN not available',
            style: TextStyle(color: Colors.teal[300], fontStyle: FontStyle.italic),
          );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 16,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal[400]!, Colors.teal[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'User Documents',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        aadharWidget,
                        SizedBox(height: 20),
                        panImageWidget,
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _approveUser(userID);
                        Navigator.pop(context);
                      },
                      icon: Icon(Icons.check, color: Colors.white),
                      label: Text('Approve', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _showRejectionDialog(userID);
                      },
                      icon: Icon(Icons.cancel, color: Colors.white),
                      label: Text('Reject', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _approveUser(String userID) async {
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
            fetchUserData();
            Fluttertoast.showToast(msg: 'Theatre owner approved successfully!');
          } else {
            Fluttertoast.showToast(msg: 'Theatre owner approval requires a valid Razorpay Account ID for payment processing.');
          }
        } else {
          Fluttertoast.showToast(msg: 'Admin verification data not found');
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error approving theatre owner: $e');
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

          fetchUserData();
          Fluttertoast.showToast(msg: 'Theatre owner application rejected!');
        } else {
          Fluttertoast.showToast(msg: 'Theatre owner data not found');
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Error rejecting theatre owner: $e');
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginApp()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade800,
        title: Text('Admin Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white)),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.pending),
              text: 'Pending Users',
            ),
            Tab(
              icon: Icon(Icons.check_circle),
              text: 'Verified Users',
            ),
            Tab(
              icon: Icon(Icons.pending_actions),
              text: 'Pending Theatres',
            ),
            Tab(
              icon: Icon(Icons.verified),
              text: 'Verified Theatres',
            ),
          ],
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.red.shade900,
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          indicatorSize: TabBarIndicatorSize.tab,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.support_agent, color: Colors.amberAccent, size: 28),
            tooltip: 'Support Tickets',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminSupportTicketsPage()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.red),
            tooltip: 'Logout',
            onPressed: () {
              _handleLogout(context);
            },
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
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildUserList(notConfirmedUsers),
            _buildUserList(confirmedUsers),
            _buildTheatreList(pendingTheatres, pending: true),
            _buildTheatreList(verifiedTheatres, pending: false),
          ],
        ),
      ),
    );
  }
}