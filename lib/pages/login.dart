import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:odp/pages/Theatre%20owner/Main%20Func/owner_home.dart';
import 'package:odp/pages/admincontroller.dart';
import 'package:odp/pages/home_page.dart';
import 'package:odp/pages/sign_up_page.dart';
import 'package:odp/pages/view_movies_guest.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'phone_login_page.dart'; // Create this file as shown below

class LoginApp extends StatefulWidget {
  const LoginApp({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginApp> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = false;
  String? _errorMessage; // For visible error messages

  final RegExp _emailRegex = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$");

  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    final prefs = await _prefs;
    final savedEmail = prefs.getString('savedEmail');
    final savedPassword = prefs.getString('savedPassword');

    if (savedEmail != null && savedPassword != null) {
      setState(() {
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
      });
    }
  }

  Future<void> _saveCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('savedEmail', email);
      await prefs.setString('savedPassword', password);
    } catch (e) {
      print('Error saving credentials: $e');
    }
  }

  Future<void> _login() async {
    setState(() {
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Input validation
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _showErrorDialog("Please enter a valid email address.");
      return;
    }
    if (password.isEmpty) {
      _showErrorDialog("Please enter your password.");
      return;
    }

    setState(() => _loading = true);

    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        final FirebaseFirestore firestore = FirebaseFirestore.instance;
        final DocumentReference userRef = firestore.collection('movie_users').doc(userCredential.user!.uid);
        final userData = await userRef.get().then((ds) => ds.data() as Map<String, dynamic>?);

        if (userData != null) {
          // First save credentials if needed
          final prefs = await SharedPreferences.getInstance();
          final savedEmail = prefs.getString('savedEmail');
          
          if (savedEmail != email) {
            // Show save credentials dialog
            if (!mounted) return;
            final shouldSave = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.teal.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: Row(
                  children: const [
                    Icon(Icons.lock_person_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'Save Login Details?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Would you like us to securely remember your email and password for faster login next time?\n\n'
                  'This is recommended only on your personal device.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Not Now',
                      style: TextStyle(
                        color: Colors.teal.shade100,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: Icon(Icons.save_alt_rounded, color: Colors.white, size: 20),
                    label: Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade900,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ) ?? false;

            if (shouldSave) {
              await _saveCredentials(email, password);
            }
          }

          // Then handle navigation based on user type
          if (!mounted) return;
          String userType = userData['userType'];
          
          if (userType == 'adminuser') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminControllersPage()),
            );
          } else if (userType == 'Theatre Owner') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage2(user: FirebaseAuth.instance.currentUser)),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage1(user: FirebaseAuth.instance.currentUser)),
            );
          }
          Fluttertoast.showToast(msg: 'Login Successful');
        } else {
          setState(() {
            _errorMessage = "User data not found.";
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showErrorDialog("User not found.");
      } else if (e.code == 'invalid-email') {
        _showErrorDialog("Invalid email format.");
      } else if (e.code == 'wrong-password') {
        _showErrorDialog("Incorrect password.");
      } else {
        _showErrorDialog("Login error: ${e.message}");
      }
    } catch (e) {
      _showErrorDialog("Login error: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    String email = _emailController.text.trim();
    if (email.isEmpty) {
      Fluttertoast.showToast(msg: 'Please enter your email address');
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: Colors.teal.shade50,
          title: Row(
            children: [
              Icon(Icons.email_outlined, color: Colors.teal.shade700),
              SizedBox(width: 10),
              Text('Check Your Email', style: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We\'ve sent a password reset link to:',
                style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.w500, fontSize: 16),
              ),
              SizedBox(height: 8),
              SelectableText(email, style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If you don\'t see the email in your inbox, please check your Spam or Junk folder. Mark it as "Not Spam" to receive future emails in your inbox.',
                      style: TextStyle(color: Colors.teal.shade800, fontSize: 15, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (e is FirebaseAuthException) {
        if (e.code == 'user-not-found') {
          Fluttertoast.showToast(msg: 'No user found for that email.');
        } else if (e.code == 'invalid-email') {
          Fluttertoast.showToast(msg: 'Invalid email format.');
        } else {
          Fluttertoast.showToast(msg: 'Error: ${e.message}');
        }
      } else {
        Fluttertoast.showToast(msg: 'Error: ${e.toString()}');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Login Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.red.shade800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Image.asset(
          'lib/assets/logo.png',
          height: 40,
          fit: BoxFit.contain,
        ),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Login',
                style: TextStyle(
                  color: Colors.teal.shade800,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              _buildTextField(
                iconData: Icons.email_outlined,
                hintText: 'Email',
                controller: _emailController,
                isObscure: false,
              ),
              const SizedBox(height: 20),

              CustomTextField(
              iconData: Icons.lock,
              hintText: "Enter Password",
              controller: _passwordController,
              isPassword: true,
              ),
              const SizedBox(height: 10),
              
              GestureDetector(
                onTap: _forgotPassword,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: _loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text(
                        'Login',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 12),

              // --- Add this for OTP Login ---
              OutlinedButton.icon(
                icon: Icon(Icons.phone_android, color: Colors.red.shade600),
                label: Text(
                  'Login with OTP',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => PhoneLoginPage()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade600, width: 2),
                  foregroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SignupPage()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade600, width: 2),
                  foregroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Sign Up',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),

              // Continue without login
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const ViewMoviesGuestPage()),
                  );
                },
                child: Text(
                  'Continue without Login',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required IconData iconData,
    required String hintText,
    required TextEditingController controller,
    required bool isObscure,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        obscureText: isObscure,
        style: TextStyle(color: Colors.red.shade900),
        cursorColor: Colors.red.shade900,
        decoration: InputDecoration(
          prefixIcon: Icon(iconData, color: Colors.red.shade800),
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.red.shade400),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }
}