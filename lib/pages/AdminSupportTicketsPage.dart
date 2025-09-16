import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:confetti/confetti.dart';

class AdminSupportTicketsPage extends StatefulWidget {
  const AdminSupportTicketsPage({Key? key}) : super(key: key);

  @override
  State<AdminSupportTicketsPage> createState() => _AdminSupportTicketsPageState();
}

class _AdminSupportTicketsPageState extends State<AdminSupportTicketsPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _refreshRotation;
  bool _isRefreshing = false;
  late ConfettiController _confettiController;
  int _listKey = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(seconds: 1));
    _refreshRotation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _confettiController = ConfettiController(duration: Duration(seconds: 2));
  }

  @override
  void dispose() {
    _controller.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    _controller.repeat();
    await Future.delayed(Duration(milliseconds: 1200));
    setState(() => _isRefreshing = false);
    _controller.reset();
  }

  void _showConfetti() {
    _confettiController.play();
  }

  void _refreshList() {
    setState(() {
      _listKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Support Tickets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white)),
        centerTitle: true,
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _refreshRotation.value * 6.28,
            child: FloatingActionButton(
              onPressed: _isRefreshing ? null : _refresh,
              backgroundColor: Colors.tealAccent,
              child: Icon(Icons.refresh, color: Colors.teal[900], size: 32),
              elevation: 10,
            ),
          );
        },
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF43CEA2), Color(0xFF185A9D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: StreamBuilder<QuerySnapshot>(
                key: ValueKey(_listKey),
                stream: FirebaseFirestore.instance
                    .collection('support_tickets')
                    .where('status', isEqualTo: 'open')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 80, color: Colors.white70),
                          SizedBox(height: 20),
                          Text('No open support tickets', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(height: 10),
                          Text('All caught up! 🎉', style: TextStyle(fontSize: 16, color: Colors.white70)),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(20),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final doc = snapshot.data!.docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return _AnimatedTicketCard(
                        ticketId: doc.id,
                        data: data,
                        onResponded: () async {
                          _showConfetti();
                          _refreshList();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: [
                Colors.tealAccent,
                Colors.blueAccent,
                Colors.purpleAccent,
                Colors.amberAccent,
                Colors.white,
              ],
              numberOfParticles: 30,
              maxBlastForce: 20,
              minBlastForce: 8,
              emissionFrequency: 0.08,
              gravity: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTicketCard extends StatefulWidget {
  final String ticketId;
  final Map<String, dynamic> data;
  final VoidCallback onResponded;
  const _AnimatedTicketCard({required this.ticketId, required this.data, required this.onResponded});

  @override
  State<_AnimatedTicketCard> createState() => _AnimatedTicketCardState();
}

class _AnimatedTicketCardState extends State<_AnimatedTicketCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _sending = false;
  final TextEditingController _responseController = TextEditingController();

  Future<bool> _sendSupportResponseEmail({
    required String ticketId,
    required String message,
  }) async {
    try {
      final url = Uri.parse('https://us-central1-turf-booking-0.cloudfunctions.net/supportApi/sendSupportAck');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: '{"ticketId": "$ticketId", "message": "$message"}',
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return AnimatedContainer(
      duration: Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      margin: EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [Colors.white.withOpacity(0.7), Colors.white.withOpacity(0.3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: _expanded ? Colors.tealAccent : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.support_agent, color: Colors.teal[700], size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      data['subject'] ?? 'No Subject',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    child: _expanded
                        ? Icon(Icons.expand_less, color: Colors.teal[700], size: 28, key: ValueKey('less'))
                        : Icon(Icons.expand_more, color: Colors.teal[700], size: 28, key: ValueKey('more')),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'From: ${data['userEmail'] ?? 'Unknown'}',
                style: TextStyle(fontSize: 14, color: Colors.teal[800]),
              ),
              SizedBox(height: 4),
              Text(
                'Status: ${data['status']}',
                style: TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
              if (_expanded) ...[
                Divider(height: 24, color: Colors.teal[200]),
                Text(
                  data['message'] ?? '',
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                SizedBox(height: 16),
                Text('Respond to Ticket:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[900], fontSize: 16)),
                SizedBox(height: 8),
                TextField(
                  controller: _responseController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Write your response here...',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sending ? null : () async {
                          setState(() => _sending = true);
                          final responseText = _responseController.text.trim();
                          final message = responseText;
                          if (message.isEmpty) {
                            setState(() => _sending = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Response message missing.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          final emailSent = await _sendSupportResponseEmail(
                            ticketId: widget.ticketId,
                            message: message,
                          );
                          if (emailSent) {
                            await FirebaseFirestore.instance.collection('support_tickets').doc(widget.ticketId).update({
                              'status': 'Closed',
                              'adminResponse': responseText,
                              'respondedAt': FieldValue.serverTimestamp(),
                            });
                            setState(() => _sending = false);
                            widget.onResponded();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.greenAccent),
                                    SizedBox(width: 8),
                                    Text('Response sent and ticket closed!'),
                                  ],
                                ),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          } else {
                            setState(() => _sending = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to send email. Please try again.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        icon: _sending
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(Icons.send, color: Colors.white),
                        label: Text('Send Response', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 6,
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
} 