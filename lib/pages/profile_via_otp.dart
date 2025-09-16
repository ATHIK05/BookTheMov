import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'login.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DottedBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF0C6157),
        Color(0xFF192028),
      ],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
    final dotPaint = Paint()..color = Colors.white.withOpacity(0.05);
    const double dotRadius = 2.0;
    const double dotSpacing = 15.0;
    for (double y = dotSpacing / 2; y < size.height; y += dotSpacing) {
      for (double x = dotSpacing / 2; x < size.width; x += dotSpacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }
  }
  @override
  bool shouldRepaint(DottedBackgroundPainter oldDelegate) => false;
}

class ProfilePageViaOtp extends StatefulWidget {
  final Map<String, dynamic> userData;
  const ProfilePageViaOtp({super.key, required this.userData});
  @override
  _ProfilePageViaOtpState createState() => _ProfilePageViaOtpState();
}

class _ProfilePageViaOtpState extends State<ProfilePageViaOtp> {
  File? _profileImage;
  bool _isEditing = false;
  bool _showSupport = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _supportSubjectController = TextEditingController();
  final TextEditingController _supportMessageController = TextEditingController();
  final GlobalKey<FormState> _supportFormKey = GlobalKey<FormState>();
  bool _isSubmittingSupport = false;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  void _fetchUserData() {
    final userData = widget.userData;
    if (userData['uid'] != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(userData['uid'])
          .get()
          .then((doc) {
        if (doc.exists) {
          setState(() {
            _userData = doc.data();
            _nameController.text = _userData?['name'] ?? '';
            _mobileController.text = _userData?['mobile'] ?? '';
          });
        }
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _profileImage = File(image.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick image. Please try again.')),
      );
    }
  }

  Future<String?> _uploadProfileImage(String uid, File imageFile) async {
    try {
      final ref = FirebaseStorage.instance.ref().child('profile_images/$uid.jpg');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _saveChanges() async {
    final userData = widget.userData;
    if (userData['uid'] != null) {
      String? imageUrl = _userData?['imageUrl'];
      if (_profileImage != null) {
        imageUrl = await _uploadProfileImage(userData['uid'], _profileImage!);
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userData['uid'])
          .update({
        'name': _nameController.text,
        'mobile': _mobileController.text,
        'imageUrl': imageUrl,
      });
      setState(() {
        _isEditing = false;
      });
      _fetchUserData();
    }
  }

  Future<void> _logout() async {
    // For OTP users, just pop to login page
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoginApp()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _showLogoutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirm Logout'),
          ],
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (result == true) {
      _logout();
    }
  }

  Future<void> _sendSupportAcknowledgementEmail(String email, String subject) async {
    final url = Uri.parse('https://cloud-functions-vnxv.onrender.com/sendSupportAck');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'subject': subject}),
      );
      if (response.statusCode != 200) {
        print('Failed to send acknowledgement email: ${response.body}');
      }
    } catch (e) {
      print('Failed to send acknowledgement email: ${e.toString()}');
    }
  }

  Future<void> _submitSupportTicket() async {
    if (!_supportFormKey.currentState!.validate()) return;
    setState(() => _isSubmittingSupport = true);
    final userData = widget.userData;
    try {
      await FirebaseFirestore.instance.collection('support_tickets').add({
        'userId': userData['uid'] ?? '',
        'userEmail': userData['email'] ?? '',
        'subject': _supportSubjectController.text.trim(),
        'message': _supportMessageController.text.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your query will be answered in 3 business days & sent to your registered email/phone number.'),
          backgroundColor: Colors.red,
        ),
      );
      if (userData['email'] != null && (userData['email'] as String).isNotEmpty) {
        await _sendSupportAcknowledgementEmail(userData['email'], _supportSubjectController.text.trim());
      }
      _supportSubjectController.clear();
      _supportMessageController.clear();
      setState(() => _showSupport = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed. Please try again later.')),
      );
    } finally {
      setState(() => _isSubmittingSupport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = widget.userData;
    final extraTopPadding =
        MediaQuery.of(context).padding.top + kToolbarHeight + 15;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'MY PROFILE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          Tooltip(
            message: _isEditing ? 'Cancel Edit' : 'Edit Profile',
            child: IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isEditing = !_isEditing;
                });
              },
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomPaint(
            painter: DottedBackgroundPainter(),
            child: Container(),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(top: extraTopPadding, bottom: 90),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: _profileImage != null
                                    ? FileImage(_profileImage!)
                                    : (_userData?['imageUrl'] != null && _userData!['imageUrl'] != ""
                                        ? NetworkImage(_userData!['imageUrl'])
                                        : const AssetImage('lib/assets/profile.png') as ImageProvider),
                              ),
                              if (_isEditing)
                                Positioned(
                                  bottom: 0,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: _pickImage,
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.black54,
                                      child: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _isEditing
                              ? Container(
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  child: TextField(
                                    controller: _nameController,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Username',
                                      hintStyle: TextStyle(color: Colors.white),
                                      border: UnderlineInputBorder(
                                        borderSide: BorderSide(color: Colors.white),
                                      ),
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(color: Colors.white),
                                      ),
                                      focusedBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(color: Colors.white),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                )
                              : Text(
                                  _userData?['name'] ?? 'Username',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Personal Information',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'FULL NAME',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _isEditing
                              ? TextField(
                                  controller: _nameController,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                  decoration: const InputDecoration(
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.teal),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.teal),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.teal),
                                    ),
                                  ),
                                )
                              : Text(
                                  _userData?['name'] ?? 'Username',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                          const SizedBox(height: 16),
                          const Text(
                            'EMAIL ADDRESS',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userData['email'] ?? 'email@example.com',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'PHONE NUMBER',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _isEditing
                              ? TextField(
                                  controller: _mobileController,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                  decoration: const InputDecoration(
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.teal),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.teal),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.teal),
                                    ),
                                  ),
                                )
                              : Text(
                                  _userData?['mobile'] ?? 'Mobile number not available',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                          const SizedBox(height: 24),
                          _isEditing
                              ? SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _saveChanges,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0C6157),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text(
                                      'SAVE CHANGES',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_isEditing)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ExpansionTile(
                            initiallyExpanded: _showSupport,
                            onExpansionChanged: (expanded) => setState(() => _showSupport = expanded),
                            leading: Icon(Icons.support_agent, color: Colors.teal[700]),
                            title: Text('Support', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[800])),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Form(
                                  key: _supportFormKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                        controller: _supportSubjectController,
                                        decoration: InputDecoration(
                                          labelText: 'Subject',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          prefixIcon: Icon(Icons.subject),
                                          filled: true,
                                          fillColor: Colors.grey[100],
                                        ),
                                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter a subject' : null,
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: _supportMessageController,
                                        decoration: InputDecoration(
                                          labelText: 'Message',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          prefixIcon: Icon(Icons.message),
                                          filled: true,
                                          fillColor: Colors.grey[100],
                                        ),
                                        minLines: 4,
                                        maxLines: 8,
                                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your message' : null,
                                      ),
                                      const SizedBox(height: 20),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          icon: _isSubmittingSupport
                                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : Icon(Icons.send),
                                          label: Text(_isSubmittingSupport ? 'Submitting...' : 'Submit Ticket', style: TextStyle(fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red.shade600,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.symmetric(vertical: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: _isSubmittingSupport ? null : _submitSupportTicket,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Divider(),
                                    Text('Previous Tickets', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 16)),
                                    const SizedBox(height: 8),
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('support_tickets')
                                          .where('userId', isEqualTo: userData['uid'] ?? '')
                                          .orderBy('createdAt', descending: true)
                                          .snapshots(),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData) {
                                          return Center(child: Padding(
                                            padding: EdgeInsets.all(8),
                                            child: CircularProgressIndicator(),
                                          ));
                                        }
                                        final tickets = snapshot.data!.docs;
                                        if (tickets.isEmpty) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text("No previous tickets found."),
                                          );
                                        }
                                        return ListView.builder(
                                          shrinkWrap: true,
                                          physics: NeverScrollableScrollPhysics(),
                                          itemCount: tickets.length,
                                          itemBuilder: (context, index) {
                                            final ticket = tickets[index];
                                            final createdAt = ticket['createdAt'] != null && ticket['createdAt'] is Timestamp
                                                ? (ticket['createdAt'] as Timestamp).toDate()
                                                : null;
                                            return Card(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              margin: EdgeInsets.only(bottom: 12),
                                              child: ListTile(
                                                leading: Icon(Icons.support_agent, color: Colors.red.shade600),
                                                title: Text(ticket['subject'] ?? 'No Subject'),
                                                subtitle: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    SizedBox(height: 4),
                                                    Text(ticket['message'] ?? ''),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      "Status: "+(ticket['status'] ?? 'open'),
                                                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                                    ),
                                                    if (createdAt != null)
                                                      Text(
                                                        "Created: "+createdAt.toString(),
                                                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 6,
                ),
                onPressed: _showLogoutDialog,
              ),
            ),
          ),
        ],
      ),
    );
  }
}