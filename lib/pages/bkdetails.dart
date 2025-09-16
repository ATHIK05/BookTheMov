import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:odp/pages/movie_booking_page.dart';

class BookingDetailsPage1 extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const BookingDetailsPage1({super.key, required this.bookingData});

  @override
  _BookingDetailsPage1State createState() => _BookingDetailsPage1State();
}

class _BookingDetailsPage1State extends State<BookingDetailsPage1> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Movie Booking Details', style: TextStyle(color: Colors.white,fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 4,
        backgroundColor: Colors.red.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMovieImage(),
                SizedBox(height: 16),
                _buildDetailRow('Movie', widget.bookingData['movieTitle'] ?? 'Unknown Movie'),
                _buildDetailRow('Theatre', widget.bookingData['theatreName'] ?? 'Unknown Theatre'),
                _buildDetailRow('Show Date', widget.bookingData['showDate'] ?? 'N/A'),
                _buildDetailRow('Show Time', widget.bookingData['showTime'] ?? 'N/A'),
                _buildDetailRow('Amount', '₹${_formatAmount(widget.bookingData['totalAmount'])}'),
                _buildDetailRow('Selected Seats', widget.bookingData['selectedSeats']?.join(', ') ?? 'N/A'),
                _buildDetailRow('Name', widget.bookingData['userName'] ?? 'Unknown User'),
                _buildDetailRow('Payment Method', widget.bookingData['paymentMethod'] ?? 'N/A'), // Add Payment Method
                _buildBookingStatus(context),
              color: Colors.red.shade700,
            ),
          ),
        ),
      ),
    );
  }

  FutureBuilder<String> _buildMovieImage() {
    String movieId = widget.bookingData['movieId'];
    return FutureBuilder<String>(
      future: _fetchMovieImageUrl(movieId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text('Error fetching image', style: TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text('No image available', style: TextStyle(color: Colors.grey)),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 250,
            builder: (context) => MovieBookingPage(
              movieId: documentId,
              theatreId: '',
              showId: '',
              showData: {},
            ),
          ),
        );
      },
    );
  }

  Future<String> _fetchMovieImageUrl(String movieId) async {
    DocumentSnapshot movieDoc = await FirebaseFirestore.instance
        .collection('movies')
        .doc(movieId)
        .get();

    if (movieDoc.exists) {
      return movieDoc['posterUrl'] ?? '';
    } else {
      throw Exception('Movie not found');
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0.00';
    
    // Convert to double and format to 2 decimal places
    double amountValue;
    if (amount is int) {
      amountValue = amount.toDouble();
    } else if (amount is double) {
      amountValue = amount;
    } else {
      try {
        amountValue = double.parse(amount.toString());
      } catch (e) {
        return '0.00';
      }
    }
    
    // Format to 2 decimal places and remove trailing zeros
    String formatted = amountValue.toStringAsFixed(2);
    if (formatted.endsWith('.00')) {
      formatted = formatted.substring(0, formatted.length - 3);
    } else if (formatted.endsWith('0')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    
    return formatted;
  }

  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                color: Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingStatus(BuildContext context) {
    final documentID = widget.bookingData['bookID'];

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('movie_bookings')
          .doc(documentID)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'Error loading booking details',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Extract booking slots and status from the snapshot
        final bookingData = snapshot.data!.data() as Map<String, dynamic>;
        final List<String> selectedSeats = List<String>.from(bookingData['selectedSeats'] ?? []);
        final String status = bookingData['status'] ?? 'confirmed';
        final currentDateTime = DateTime.now();
        final showDate = widget.bookingData['showDate'];
        final showTime = widget.bookingData['showTime'];
        bool isCancelling = false;
        bool canCancel = false;

        // Check if booking can be cancelled (3+ hours before show)
        if (showDate != null && showTime != null) {
          try {
            final showDateTime = DateTime.parse('$showDate $showTime');
            canCancel = showDateTime.isAfter(currentDateTime) && 
                       showDateTime.difference(currentDateTime).inHours >= 3;
          } catch (e) {
            canCancel = false;
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              SizedBox(height: 8),
              Column(
                children: [
                  // Selected Seats
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_seat, color: Colors.red.shade600),
                        SizedBox(width: 8),
                        Text(
                          'Seats: ${selectedSeats.join(', ')}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  
                  // Booking Status
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: status == 'confirmed' ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          status == 'confirmed' ? Icons.check_circle : Icons.pending,
                          color: status == 'confirmed' ? Colors.green : Colors.orange,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Status: ${status.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: status == 'confirmed' ? Colors.green.shade800 : Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Cancel Button (if applicable)
                  if (canCancel && status == 'confirmed') ...[
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isCancelling ? null : () async {
                          setState(() {
                            isCancelling = true;
                          });
                          await _cancelMovieBooking(documentID);
                          setState(() {
                            isCancelling = false;
                          });
                        },
                        icon: isCancelling 
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(Icons.cancel, color: Colors.white),
                        label: Text(
                          isCancelling ? 'Cancelling...' : 'Cancel Booking',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _cancelMovieBooking(String bookingId) async {
  try {
    // Update booking status to cancelled
    await FirebaseFirestore.instance
        .collection('movie_bookings')
        .doc(bookingId)
        .update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
    
    print('Movie booking cancelled successfully: $bookingId');
  } catch (e) {
    print('Error cancelling movie booking: $e');
  }
}