import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:odp/pages/movie_booking_details.dart';

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  _BookingsPageState createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage>
    with SingleTickerProviderStateMixin {
  final _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  late TabController _tabController;
  bool selectionMode = false;
  List<Map<String, dynamic>> selectedBookings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<List<DocumentSnapshot>> _fetchBookings() {
    return FirebaseFirestore.instance
        .collection('movie_bookings')
        .where('userId', isEqualTo: _currentUserId)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  void _enableSelectionMode(Map<String, dynamic> bookingData, String bookingType) {
    // Prevent selection for upcoming bookings
    if (bookingType == 'upcoming') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('Not Allowed'),
            ],
          ),
          content: Text('Upcoming bookings cannot be deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      selectionMode = true;
      selectedBookings = [
        {
          'bookID': bookingData['bookID'],
          'data': bookingData,
          'type': bookingType,
        }
      ];
    });
  }

  void _toggleBookingSelection(Map<String, dynamic> bookingData, String bookingType) {
    setState(() {
      final existingIndex = selectedBookings.indexWhere((b) => b['bookID'] == bookingData['bookID']);
      if (existingIndex >= 0) {
        selectedBookings.removeAt(existingIndex);
        if (selectedBookings.isEmpty) {
          selectionMode = false;
        }
      } else {
        selectedBookings.add({
          'bookID': bookingData['bookID'],
          'data': bookingData,
          'type': bookingType,
        });
      }
    });
  }

  void _resetSelectedBookings() {
    setState(() {
      selectedBookings.clear();
      selectionMode = false;
    });
  }

  void _deleteSelectedBookings() async {
    bool deletionSuccessful = true;

    for (var booking in selectedBookings) {
      String bookID = booking['bookID'];

      try {
        var bookingRef =
            FirebaseFirestore.instance.collection('movie_bookings').doc(bookID);
        await bookingRef.delete();
        print('Booking with ID: $bookID has been deleted successfully');
      } catch (e) {
        print('Failed to delete booking with ID: $bookID');
        deletionSuccessful = false;
      }
    }

    if (deletionSuccessful) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selected movie bookings have been deleted successfully from history')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some bookings failed to delete')),
      );
    }

    setState(() {
      selectionMode = false;
      selectedBookings.clear();
    });
  }

  Widget _buildBookingsSection(String state) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _fetchBookings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: CircularProgressIndicator(
                color: Colors.red,
                strokeWidth: 3,
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error fetching bookings',
                style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState();
        }

        var bookings = snapshot.data!;
        var filteredBookings = bookings.where((booking) {
          var bookingData = booking.data() as Map<String, dynamic>;
          return bookingData['userId'] == _currentUserId;
        }).toList();

        var upcomingBookings = filteredBookings.where((booking) {
          var bookingData = booking.data() as Map<String, dynamic>;
          var bookingDate =
              DateTime.tryParse(bookingData['bookingDate'] ?? '') ??
                  DateTime.now();
          return bookingDate.isAfter(DateTime.now()) &&
              (bookingData['bookingSlots']?.isNotEmpty ?? false) &&
              (bookingData['status'] != 'cancelled');
        }).toList();

        var pastBookings = filteredBookings.where((booking) {
          var bookingData = booking.data() as Map<String, dynamic>;
          var bookingDate =
              DateTime.tryParse(bookingData['bookingDate'] ?? '') ??
                  DateTime.now();
          return bookingDate.isBefore(DateTime.now()) &&
              (bookingData['bookingSlots']?.isNotEmpty ?? false) &&
              (bookingData['status'] != 'cancelled');
        }).toList();

        var cancelledBookings = filteredBookings.where((booking) {
          var bookingData = booking.data() as Map<String, dynamic>;
          return bookingData['status'] == 'cancelled' ||
              (bookingData['bookingSlots']?.isEmpty ?? true);
        }).toList();

        List<DocumentSnapshot> displayBookings = [];
        if (state == 'upcoming') {
          displayBookings = upcomingBookings;
        } else if (state == 'past') {
          displayBookings = pastBookings;
        } else if (state == 'cancelled') {
          displayBookings = cancelledBookings;
        }

        if (displayBookings.isEmpty) {
          return _buildEmptyState();
        }

        return Stack(
          children: [
            ListView.separated(
              itemCount: displayBookings.length,
              padding: const EdgeInsets.only(top: 18, left: 12, right: 12, bottom: 80),
              separatorBuilder: (context, index) => SizedBox(height: 14),
              itemBuilder: (context, index) {
                var bookingData =
                    displayBookings[index].data() as Map<String, dynamic>;
                bookingData['bookID'] = displayBookings[index].id;

                final isSelected = selectedBookings.any((b) => b['bookID'] == bookingData['bookID']);

                return Hero(
                  tag: 'booking_${bookingData['bookID']}',
                  child: GestureDetector(
                    onLongPress: () {
                      if (!selectionMode) {
                        _enableSelectionMode(bookingData, state);
                      }
                    },
                    onTap: () {
                      if (selectionMode) {
                        _toggleBookingSelection(bookingData, state);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BookingDetailsPage1(
                              bookingData: bookingData,
                            ),
                          ),
                        );
                      }
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.red.shade50
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.07),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isSelected
                              ? Colors.red
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    bookingData['movieTitle'] ?? 'No Movie Title',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.red,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusBadge(
                                    status: bookingData['status'] ?? 'confirmed'),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.movie, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  '${bookingData['showDate'] ?? 'No Date'} at ${bookingData['showTime'] ?? 'No Time'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.event_seat, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  'Seats: ${(bookingData['selectedSeats'] as List?)?.join(', ') ?? 'No Seats'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // --- Theatre Name Column ---
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Theatre',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      bookingData['theatreName'] ?? 'No Theatre',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                // --- Price Column ---
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'Price',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      bookingData['totalAmount'] != null
                                          ? '₹${(bookingData['totalAmount'] as num).toStringAsFixed(2)}'
                                          : 'No Price',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BookingDetailsPage1(
                                      bookingData: bookingData,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Details'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade600,
                                minimumSize: const Size(double.infinity, 36),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                side: const BorderSide(color: Color(0xFFDCECFD)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // --- Instruction at the bottom ---
            if (state == 'cancelled' || state == 'past')
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200]?.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app, size: 16, color: Colors.grey[600]),
                          SizedBox(width: 8),
                          Text(
                            'Long press a movie booking to select and delete it.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            color: Colors.red.shade200,
            size: 100,
          ),
          SizedBox(height: 28),
          Text(
            'No bookings found',
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 0.1,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'You have no bookings in this category.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

    @override
Widget build(BuildContext context) {
  return DefaultTabController(
    length: 3,
    child: WillPopScope(
      onWillPop: () async {
        if (selectionMode) {
          setState(() {
            selectedBookings.clear();
            selectionMode = false;
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        // AppBar removed
        body: Column(
          children: [
            SizedBox(height: 18),
            // TabBar remains at the top
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.shade500,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelColor: Colors.red.shade800,
                  unselectedLabelColor: Colors.white,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  indicatorPadding: EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                  tabs: const [
                    Tab(text: '   Upcoming    '),
                    Tab(text: '  Past Bookings  '),
                    Tab(text: '   Cancelled   '),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildBookingsSection('upcoming'),
                  _buildBookingsSection('past'),
                  _buildBookingsSection('cancelled'),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: selectionMode
            ? FloatingActionButton.extended(
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                backgroundColor: Colors.red.shade600,
                label: Text(
                  'Delete (${selectedBookings.length})',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      titlePadding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                      contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      actionsPadding: EdgeInsets.only(right: 16, bottom: 12),
                      title: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 28),
                          SizedBox(width: 10),
                          Text(
                            "Confirm Deletion",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ],
                      ),
                      content: Text(
                        "Are you sure you want to delete ${selectedBookings.length} bookings? This action cannot be undone.",
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            "Cancel",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: Icon(Icons.delete_forever, color: Colors.white, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          label: Text(
                            "Delete",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) _deleteSelectedBookings();
                },
              )
            : null,
      ),
    ),
    );
  }

  }

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label = status[0].toUpperCase() + status.substring(1);

    switch (status) {
      case 'confirmed':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'pending':
        color = Colors.amber;
        icon = Icons.error;
        break;
      case 'completed':
        color = Colors.blue;
        icon = Icons.check_circle;
        break;
      case 'cancelled':
        color = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        color = Colors.green;
        icon = Icons.check_box_sharp;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}