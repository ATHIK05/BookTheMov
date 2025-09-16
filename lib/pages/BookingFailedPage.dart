import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart'; // Import Lottie package
import 'home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:odp/pages/movie_booking_page.dart';

class BookingFailedPage extends StatelessWidget {
  final String documentId;
  final String documentname;
  final String userId;

  const BookingFailedPage({
    super.key,
    required this.documentId,
    required this.documentname,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MovieBookingPage(
              movieId: documentId,
              theatreId: '',
              showId: '',
              showData: const {},
            ),
          ),
        );
        return false;
      },
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.network(
                'https://lottie.host/7c1cebac-5af7-4b12-8a2b-d61b749fb5ce/XEIb6NoIEU.json', // Lottie animation URL
                height: 350, // Adjust the height as needed
                width: 350, // Adjust the width as needed
              ),
              SizedBox(height: 20),
              Text(
                'Oops Failed Try Again Later!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,color: Colors.red),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                child: Text('Payment Failed Try Again!',style: TextStyle(
                  color: Colors.red, // Set text color to bright green
                  fontSize: 18, // Adjust font size as needed
                ),),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MovieBookingPage(
                        movieId: documentId,
                        theatreId: '',
                        showId: '',
                        showData: {},
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
