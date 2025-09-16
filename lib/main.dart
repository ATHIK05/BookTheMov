import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:odp/pages/StartPage.dart';
import 'package:odp/pages/Theatre%20owner/Main%20Func/owner_home.dart';
import 'package:odp/pages/admincontroller.dart';
import 'package:odp/pages/home_page.dart';
import 'package:odp/pages/login.dart';
import 'package:odp/pages/view_movies_guest.dart';
import 'package:odp/services/fcm_service.dart';
// Make sure to import or define SignupPage() in your project.
import 'firebase_options.dart';
import 'dart:ui';

// -------------- ADD THIS NEW StartPage() FILE OR CODE SNIPPET BELOW --------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully.');
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookMyBiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        primaryColor: Colors.red[900],
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red[900]!,
          brightness: Brightness.light,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      routes: {
        '/login': (context) => LoginApp(),
        '/guest': (context) => ViewMoviesGuestPage(),
        // ...other routes...
      },
      home: SplashScreen(), // Start with splash screen
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('Firebase initialized successfully.');

      // Initialize FCM service
      await FCMService.initialize();
      print('FCM service initialized successfully.');

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _controller.forward();

        Future.delayed(Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => AuthWrapper()),
            );
          }
        });
      }
    } catch (e) {
      print('Error initializing Firebase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing app. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildGlassIconBox() {
    return ScaleTransition(
      scale: _animation,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withOpacity(0.3),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          child: Center(
            child: Icon(Icons.movie, size: 80, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildAppName() {
    return FadeTransition(
      opacity: _animation,
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: const [Colors.tealAccent, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
        child: Text(
          'BookMyBiz',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red[900]!, Colors.red[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildGlassIconBox(),
            SizedBox(height: 30),
            if (_isInitialized) _buildAppName(),
          ],
        ),
      ),
      ),
    );
  }
}
// ---------------------- AUTH WRAPPER ----------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // If user is admin
      if (user.email == 'adminpunchbiz@gmail.com') {
        return AdminControllersPage();
      }
      // Otherwise, check user type from Firestore
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('movie_users').doc(user.uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // You can reuse the splash screen or show a loader
            return SplashScreen();
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading user data'));
          }
          if (snapshot.hasData && snapshot.data != null) {
            var userType = snapshot.data!.get('userType');
            if (userType == 'Theatre Owner') {
              return HomePage2(user: user);
            } else {
              return HomePage1(user: user);
            }
          }
          // Fallback to StartPage if user data not found
          return StartPage();
        },
      );
    } else {
      // <--- HERE: Navigate to StartPage() instead of LoginApp() --->
      return StartPage();
    }
  }
}

// -----------------------------------------------------------
// Optionally, start a performance trace if you use Firebase Performance
void startPerformanceTrace() async {
  final Trace trace = FirebasePerformance.instance.newTrace('auth_wrapper_trace');
  trace.start();
  await Future.delayed(const Duration(seconds: 1));
  trace.stop();
}
