const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Razorpay = require('razorpay');
const axios = require('axios');

// Initialize Firebase Admin
admin.initializeApp();

// Initialize Razorpay client
function getRazorpayClient() {
  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  
  if (!keyId || !keySecret) {
    throw new Error('Razorpay environment variables RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET not set');
  }
  
  return new Razorpay({
    key_id: keyId,
    key_secret: keySecret
  });
}

// Function to update payout status
async function updatePayoutStatus(snap, status, reason) {
  try {
    await snap.ref.update({
      payoutStatus: status,
      payoutError: reason
    });
  } catch (error) {
    console.error('Error updating payout status:', error);
  }
}

// Function to update movie booking after successful transfer
async function updateMovieBookingAfterTransfer(snap, status, transferResp, ownerAccountId) {
  try {
    await snap.ref.update({
      payoutStatus: status,
      transferResponse: transferResp,
      theatreOwnerAccountId: ownerAccountId,
      payoutMethod: 'Razorpay Route'
    });
  } catch (error) {
    console.error('Error updating movie booking after transfer:', error);
  }
}

// Function to resolve theatre owner account ID from theatre and user data
async function resolveTheatreOwnerAccountId(theatreId, bookingData) {
  if (!theatreId) return null;
  
  try {
    const db = admin.firestore();
    const theatreDoc = await db.collection('movie_theatres').doc(theatreId).get();
    
    if (!theatreDoc.exists) return null;
    
    const theatre = theatreDoc.data();
    const ownerId = theatre.ownerId || bookingData.ownerId;
    
    if (!ownerId) return null;
    
    const userDoc = await db.collection('users').doc(ownerId).get();
    
    if (!userDoc.exists) return null;
    
    const user = userDoc.data();
    
    // Try common field names for Razorpay connected account id
    const candidateKeys = [
      'razorpayAccountId', 'ownerAccountId', 'accountId', 'razorpay_account_id', 'razorpay_accountId'
    ];
    
    for (const key of candidateKeys) {
      const acc = user[key];
      if (typeof acc === 'string' && acc.startsWith('acc_')) {
        return acc;
      }
    }
    
    return null;
  } catch (error) {
    console.error('Error resolving theatre owner account ID:', error);
    return null;
  }
}

// Main function: triggered when a new booking is created
exports.onMovieBookingCreated = functions.firestore
  .document('movie_bookings/{bookingId}')
  .onCreate(async (snap, context) => {
    try {
      const data = snap.data();
      
      // Only process online confirmed payments with pending payout
      if (data.paymentMethod !== 'Online') {
        console.log('Skipping: Not an online payment');
        return;
      }
      if (data.status !== 'confirmed') {
        console.log('Skipping: Payment not confirmed');
        return;
      }
      if (data.payoutStatus === 'settled') {
        console.log('Skipping: Payout already settled');
        return;
      }

      const totalAmount = parseFloat(data.totalAmount) || 0;
      const actualTicketPrice = parseFloat(data.actualTicketPrice) || 0;
      let ownerAccountId = data.theatreOwnerAccountId;
      const paymentId = data.razorpayPaymentId;
      const theatreId = data.theatreId;

      console.log(`Processing booking: ${context.params.bookingId}, Amount: ${totalAmount}, Theatre: ${theatreId}`);

      // Guard clauses
      if (totalAmount <= 0) {
        await updatePayoutStatus(snap, 'failed', 'Invalid amount');
        return;
      }

      if (!ownerAccountId || ownerAccountId === 'owner_placeholder') {
        // Try to resolve from theatre -> users collection
        try {
          ownerAccountId = await resolveTheatreOwnerAccountId(theatreId, data);
        } catch (error) {
          await updatePayoutStatus(snap, 'failed', `Owner account resolution error: ${error.message}`);
          return;
        }
        
        if (!ownerAccountId) {
          await updatePayoutStatus(snap, 'failed', 'Missing Razorpay connected account ID. Theatre owner must add their Razorpay account ID to receive payments.');
          return;
        }
      }

      if (!paymentId) {
        await updatePayoutStatus(snap, 'failed', 'Missing Razorpay payment ID for transfer');
        return;
      }

      if (!ownerAccountId.startsWith('acc_')) {
        await updatePayoutStatus(snap, 'failed', 'Theatre owner does not have a valid Razorpay connected account ID.');
        return;
      }

      // Calculate owner's share internally (confidential business logic)
      const ownerShare = calculateTheatreOwnerShare(actualTicketPrice);
      const companyProfit = totalAmount - ownerShare;
      console.log(`Total amount paid by customer: ${totalAmount}`);
      console.log(`Theatre owner share (88% of ticket price): ${ownerShare}`);
      console.log(`Company keeps (profit + fees): ${companyProfit}`);

      // Check if theatre owner has Razorpay connected account
      const ownerPaymentMethod = await getTheatreOwnerPaymentMethod(ownerAccountId, theatreId, data);
      
      const client = getRazorpayClient();
      
      if (ownerPaymentMethod.type === 'razorpay') {
        // Use Razorpay Route transfer
        await processRazorpayTransfer(client, paymentId, ownerShare, ownerPaymentMethod.accountId);
      } else {
        throw new Error('No valid payment method found for theatre owner');
      }

      // Update booking with transfer details
      await updateMovieBookingAfterTransfer(snap, 'settled', null, ownerAccountId);
      
      // Save profit/owner share info in Firestore for tracking
      const db = admin.firestore();
      await db.collection('movie_booking_settlements').doc(context.params.bookingId).set({
        booking_id: context.params.bookingId,
        theatre_id: theatreId || null,
        total_paid: totalAmount,
        owner_share: ownerShare,
        platform_profit: companyProfit,
        razorpay_payment_id: paymentId,
        owner_account_id: ownerAccountId,
        settledAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`Successfully processed payout for booking ${context.params.bookingId}`);
      
    } catch (error) {
      console.error('Function execution error:', error);
      try {
        await updatePayoutStatus(snap, 'failed', `Function error: ${error.message}`);
      } catch (updateError) {
        console.error('Failed to update payout status:', updateError);
      }
    }
  });

// Calculate theatre owner share (88% of actual ticket price)
function calculateTheatreOwnerShare(actualTicketPrice) {
  return actualTicketPrice; // Theatre owner gets 100% of base ticket price (not 88%)
}

// Function to determine theatre owner's payment method (Razorpay only)
async function getTheatreOwnerPaymentMethod(ownerAccountId, theatreId, bookingData) {
  if (ownerAccountId && ownerAccountId.startsWith('acc_')) {
    return {
      type: 'razorpay',
      accountId: ownerAccountId
    };
  }
  throw new Error('No valid Razorpay connected account ID for theatre owner.');
}

// Function to process Razorpay Route transfer
async function processRazorpayTransfer(client, paymentId, ownerShare, accountId) {
  try {
    const amountInPaise = Math.round(ownerShare * 100);
    
    const transferResp = await client.payment.transfer(paymentId, {
      transfers: [
        {
          account: accountId,
          amount: amountInPaise,
          currency: 'INR',
          notes: {
            purpose: 'Movie ticket booking settlement - 100% of base ticket price',
            note: 'Platform fee (12%) collected separately from customer'
          }
        }
      ]
    });
    
    console.log(`Razorpay transfer successful: ${amountInPaise} paise to ${accountId}`);
    return transferResp;
    
  } catch (error) {
    console.error('Razorpay transfer failed:', error);
    throw error;
  }
}

// Add callable function to create Razorpay order with transfer split for movie bookings
exports.createMovieBookingRazorpayOrder = functions.https.onCall(async (data, context) => {
  try {
    const { actualTicketPrice, totalAmount, ownerAccountId, bookingId, theatreId, currency = 'INR' } = data;
    if (!actualTicketPrice || !totalAmount || !ownerAccountId || !bookingId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }
    if (!ownerAccountId.startsWith('acc_')) {
      throw new functions.https.HttpsError('failed-precondition', 'Theatre Owner Razorpay Account ID is invalid');
    }
    const client = getRazorpayClient();
    
    // actualTicketPrice = base ticket amount
    // totalAmount = total amount customer pays (including platform fee)
    const ownerShare = calculateTheatreOwnerShare(actualTicketPrice); // 100% of ticket price
    const platformProfit = totalAmount - ownerShare; // Platform keeps 12% + fees
    
    const order = await client.orders.create({
      amount: Math.round(totalAmount * 100), // Customer pays the full amount
      currency,
      transfers: [
        {
          account: ownerAccountId,
          amount: Math.round(ownerShare * 100), // Theatre owner gets 100% of ticket price
          currency,
          notes: {
            booking_id: bookingId,
            owner_share: ownerShare.toString()
          }
        }
      ],
      notes: {
        booking_id: bookingId,
        owner_share: ownerShare.toString(),
        platform_profit: platformProfit.toString(),
        actual_ticket_price: actualTicketPrice.toString()
      }
    });
    // Save profit/owner share info in Firestore for tracking
    const db = admin.firestore();
    await db.collection('movie_razorpay_orders').doc(order.id).set({
      booking_id: bookingId,
      theatre_id: theatreId || null,
      total_paid: totalAmount, // What customer paid
      actual_ticket_price: actualTicketPrice, // Base ticket price
      owner_share: ownerShare,
      platform_profit: platformProfit,
      razorpay_order_id: order.id,
      owner_account_id: ownerAccountId,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    return {
      orderId: order.id,
      ownerShare,
      platformProfit,
      actualTicketPrice: actualTicketPrice,
      amount: totalAmount
    };
  } catch (error) {
    console.error('Error creating movie booking Razorpay order with transfer:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// --- Support Ticket Email Acknowledgement Endpoint ---
const express = require('express');
const bodyParser = require('body-parser');
const nodemailer = require('nodemailer');

const supportApp = express();
supportApp.use(bodyParser.json());

const TRANSPORTS = {
  User: nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: 'customersbmb@gmail.com',
      pass: 'fofb axss moce zspb'
    }
  }),
  Other: nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: 'ownersbmb@gmail.com',
      pass: 'uqec eqiq ipti zbhp'
    }
  })
};

supportApp.post('/sendSupportAck', async (req, res) => {
  const { ticketId, message } = req.body;
  if (!ticketId) {
    res.status(400).send('Missing ticketId');
    return;
  }
  try {
    // 1. Fetch the support ticket
    const ticketDoc = await admin.firestore().collection('support_tickets').doc(ticketId).get();
    if (!ticketDoc.exists) {
      res.status(404).send('Support ticket not found');
      return;
    }
    const ticket = ticketDoc.data();
    const userId = ticket.userId;
    const subject = ticket.subject || '';
    const userEmail = ticket.userEmail || '';
    // 2. Fetch the user
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) {
      res.status(404).send('User not found');
      return;
    }
    const user = userDoc.data();
    const userName = user.name || 'User';
    const userType = user.userType || 'User';
    // 3. Choose transporter
    const transporter = userType === 'User' ? TRANSPORTS.User : TRANSPORTS.Other;
    const fromEmail = userType === 'User'
      ? 'BookMyBiz Support <customersbmb@gmail.com>'
      : 'BookMyBiz Support <ownersbmb@gmail.com>';
    // 4. Compose email
    let emailText = `Dear ${userName},\n\n`;
    if (message && message.trim() !== '') {
      emailText += `Admin Response: ${message.trim()}\n\n`;
    } else {
      emailText += `We have received your support ticket (Subject: ${subject}). Our team will respond within 3 business days to your registered email/phone number.\n\n`;
    }
    emailText += `Thank you for contacting us!\n\n- BookMyBiz Support`;
    const mailOptions = {
      from: fromEmail,
      to: userEmail,
      subject: 'Support Ticket Update',
      text: emailText
    };
    await transporter.sendMail(mailOptions);
    res.status(200).send('Email sent!');
  } catch (error) {
    console.error('Error sending email:', error);
    res.status(500).send('Failed to send email');
  }
});

// Export the express app as a Cloud Function
exports.supportApi = functions.https.onRequest(supportApp);

// --- Movie Booking Confirmation Email (Callable) ---
exports.sendMovieBookingConfirmationEmail = functions.https.onCall(async (data, context) => {
  try {
    const {
      to,
      userName = 'Customer',
      bookingId = '',
      movieTitle = '',
      theatreName = '',
      showDate = '',
      showTime = '',
      selectedSeats = [],
      amount = 0,
      paymentMethod = 'Online'
    } = data || {};

    if (!to || typeof to !== 'string' || !to.includes('@')) {
      throw new functions.https.HttpsError('invalid-argument', 'Valid recipient email (to) is required');
    }

    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: 'customersbmb@gmail.com',
        pass: 'fofb axss moce zspb'
      }
    });

    const path = require('path');
    const appLogoPath = path.resolve(__dirname, 'assets', 'app.png');
    const companyLogoPath = path.resolve(__dirname, 'assets', 'logo.png');

    const prettyDate = showDate || new Date().toISOString().slice(0, 10);
    const seatsList = Array.isArray(selectedSeats) ? selectedSeats.join(', ') : '';
    const subject = `Movie Booking Confirmed • ${movieTitle} • ${prettyDate}`;

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Booking Confirmation</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
</head>
<body style="margin:0; padding:0; background-color:#f5f5f5; font-family: Arial, sans-serif; color:#333333;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#f5f5f5; width:100%;">
<tr>
  <td align="center" style="padding: 20px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; background-color:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 0 10px rgba(0,0,0,0.1);">
      <!-- Header -->
      <tr>
        <td style="background-color:#0f766e; padding:20px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
            <tr>
              <td align="left" style="width:50%;">
                <img src="cid:companyLogo" alt="Company Logo" width="120" style="display:block; max-width:120px; height:auto;">
              </td>
              <td align="right" style="width:50%;">
                <img src="cid:appLogo" alt="App Logo" width="50" style="display:block; max-width:50px; height:auto;">
              </td>
            </tr>
            <tr>
              <td colspan="2" align="center" style="padding:20px 0 10px 0;">
                <h1 style="color:#ffffff; font-size:22px; line-height:28px; font-weight:bold; margin:0;">Your Booking is Confirmed</h1>
              </td>
            </tr>
          </table>
        </td>
      </tr>
      <!-- Greeting -->
      <tr>
        <td style="padding:20px;">
          <p style="margin:0; font-size:16px; line-height:24px;">Hi <strong>${userName}</strong>, thanks for booking with us. Here are your booking details:</p>
        </td>
      </tr>
      <!-- Booking Details -->
      <tr>
        <td style="padding:0 20px 20px 20px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%; border-collapse: collapse; font-size:14px;">
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Booking ID:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${bookingId}</td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Movie:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${movieTitle}</td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Theatre:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${theatreName}</td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Show Date:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${prettyDate}</td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Show Time:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${showTime}</td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Selected Seats:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${seatsList}</td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Amount Paid:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><span style="color:#0f766e; font-weight:bold;">₹${Number(amount || 0).toFixed(2)}</span></td>
            </tr>
            <tr>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;"><strong>Payment Method:</strong></td>
              <td style="padding:10px 0; border-bottom:1px solid #e0e0e0;">${paymentMethod}</td>
            </tr>
          </table>
        </td>
      </tr>
      <!-- Footer -->
      <tr>
        <td style="background-color:#f9fafb; padding:15px 20px; text-align:center; font-size:12px; color:#6b7280;">
          If you have questions, reply to this email or contact support.<br>
          © ${new Date().getFullYear()} BookMyBiz • All rights reserved
        </td>
      </tr>
    </table>
  </td>
</tr>
</table>
</body>
</html>`;

    const mailOptions = {
      from: 'BookMyBiz <customersbmb@gmail.com>',
      to,
      subject,
      html,
      attachments: [
        { filename: 'app.png', path: appLogoPath, cid: 'appLogo' },
        { filename: 'logo.png', path: companyLogoPath, cid: 'companyLogo' }
      ]
    };

    const info = await transporter.sendMail(mailOptions);
    return { ok: true, id: info.messageId };
  } catch (error) {
    console.error('sendMovieBookingConfirmationEmail error:', error);
    throw new functions.https.HttpsError('internal', error.message || 'Failed to send email');
  }
});


// --- FCM Notification Functions ---
async function sendNotificationToAdmin(title, body, data = {}) {
  try {
    // Get admin user document to find their FCM token
    const adminQuery = await admin.firestore()
      .collection('users')
      .where('email', '==', 'adminpuncbiz@gmail.com')
      .limit(1)
      .get();

    if (adminQuery.empty) {
      console.log('Admin user not found');
      return;
    }

    const adminDoc = adminQuery.docs[0];
    const adminData = adminDoc.data();
    const fcmToken = adminData.fcmToken;

    if (!fcmToken) {
      console.log('Admin FCM token not found');
      return;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: fcmToken,
      android: {
        notification: {
          channel_id: 'verification_channel',
          priority: 'high',
          default_sound: true,
          default_vibrate_timings: true,
          icon: 'app', // Added app icon for all notifications
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log('Successfully sent notification:', response);
    return response;
  } catch (error) {
    console.error('Error sending notification:', error);
    throw error;
  }
}

// Function to send notification to theatre owner
async function sendNotificationToTheatreOwner(ownerId, title, body, data = {}) {
  try {
    // Get theatre owner document to find their FCM token
    const ownerDoc = await admin.firestore().collection('users').doc(ownerId).get();
    
    if (!ownerDoc.exists) {
      console.log('Theatre owner not found:', ownerId);
      return;
    }

    const ownerData = ownerDoc.data();
    const fcmToken = ownerData.fcmToken;

    if (!fcmToken) {
      console.log('Theatre owner FCM token not found:', ownerId);
      return;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: fcmToken,
      android: {
        notification: {
          channel_id: 'theatre_status_channel',
          priority: 'high',
          default_sound: true,
          default_vibrate_timings: true,
          icon: 'app', // Added app icon for all notifications
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log('Successfully sent notification to theatre owner:', response);
    return response;
  } catch (error) {
    console.error('Error sending notification to theatre owner:', error);
    throw error;
  }
}

// Function to handle theatre approval
exports.onTheatreApproved = functions.firestore
  .document('movie_theatres/{theatreId}')
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      
      // Check if status changed from 'Not Verified' to 'Verified'
      if (beforeData.theatre_status === 'Not Verified' && afterData.theatre_status === 'Verified') {
        const ownerId = afterData.ownerId;
        const theatreName = afterData.name || 'Your theatre';
        
        if (ownerId) {
          await sendNotificationToTheatreOwner(
            ownerId,
            'Theatre Approved! 🎉',
            `Congratulations! Your theatre "${theatreName}" has been approved and is now visible to users.`,
            {
              type: 'theatre_approved',
              theatreId: context.params.theatreId,
              theatreName: theatreName,
              timestamp: new Date().toISOString(),
            }
          );
          console.log('Theatre approval notification sent to owner:', ownerId);
        }
      }
    } catch (error) {
      console.error('Error in onTheatreApproved:', error);
    }
  });

// Function to handle theatre rejection
exports.onTheatreRejected = functions.firestore
  .document('movie_theatres/{theatreId}')
  .onUpdate(async (change, context) => {
    try {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      
      // Check if status changed from 'Not Verified' to 'Disapproved'
      if (beforeData.theatre_status === 'Not Verified' && afterData.theatre_status === 'Disapproved') {
        const ownerId = afterData.ownerId;
        const theatreName = afterData.name || 'Your theatre';
        const rejectionReason = afterData.rejectionReason || 'No reason provided';
        
        if (ownerId) {
          await sendNotificationToTheatreOwner(
            ownerId,
            'Theatre Review Update',
            `Your theatre "${theatreName}" requires changes. Please review the feedback and resubmit.`,
            {
              type: 'theatre_rejected',
              theatreId: context.params.theatreId,
              theatreName: theatreName,
              rejectionReason: rejectionReason,
              timestamp: new Date().toISOString(),
            }
          );
          console.log('Theatre rejection notification sent to owner:', ownerId);
        }
      }
    } catch (error) {
      console.error('Error in onTheatreRejected:', error);
    }
  });

exports.onTheatreCreated = functions.firestore
  .document('movie_theatres/{theatreId}')
  .onCreate(async (snap, context) => {
    try {
      const theatreData = snap.data();
      const ownerId = theatreData.ownerId;
      let ownerName = theatreData.name || 'A Theatre Owner';

      // Optionally fetch more owner details if needed
      if (ownerId) {
        const userDoc = await admin.firestore().collection('users').doc(ownerId).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          ownerName = userData.name || ownerName;
        }
      }

      await sendNotificationToAdmin(
        'New Theatre Added',
        `${ownerName} added a new theatre, kindly review it`,
        {
          type: 'theatre_added',
          theatreId: context.params.theatreId,
          ownerId: ownerId,
          ownerName: ownerName,
          timestamp: new Date().toISOString(),
        }
      );
      console.log('Admin notified for new theatre:', context.params.theatreId);
    } catch (error) {
      console.error('Error notifying admin for new theatre:', error);
    }
  });
// Function to send notification when user submits verification details
exports.onUserVerificationSubmitted = functions.firestore
  .document('documents/{userId}')
  .onCreate(async (snap, context) => {
    try {
      const documentData = snap.data();
      const userId = context.params.userId;

      // Get user details
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (!userDoc.exists) {
        console.log('User document not found');
        return;
      }

      const userData = userDoc.data();
      const userName = userData.name || 'Unknown User';
      const userEmail = userData.email || 'No email';

      // Send notification to admin
      await sendNotificationToAdmin(
        'New User Verification Submitted',
        `User ${userName} has submitted verification details for review`,
        {
          type: 'verification_submitted',
          userId: userId,
          userName: userName,
          userEmail: userEmail,
          timestamp: new Date().toISOString(),
        }
      );

      console.log('Verification notification sent for user:', userId);
    } catch (error) {
      console.error('Error in onUserVerificationSubmitted:', error);
    }
  });

// Function to handle movie booking refund request creation
exports.createMovieBookingRefundRequest = functions.https.onCall(async (data, context) => {
  try {
    const {
      bookingId,
      userId,
      theatreId,
      amount,
      paymentId,
      reason = 'User requested cancellation',
      showDate,
      movieTitle,
      theatreName,
      selectedSeats
    } = data;

    if (!bookingId || !userId || !amount || !paymentId) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    const db = admin.firestore();
    
    // Get base amount from booking data
    const bookingDoc = await db.collection('movie_bookings').doc(bookingId).get();
    const bookingData = bookingDoc.exists ? bookingDoc.data() : {};
    const actualTicketPrice = bookingData.actualTicketPrice || (parseFloat(amount) * 0.88); // 88% for theatre owner
    
    // Create refund request document
    const refundRequest = {
      bookingId,
      userId,
      theatreId,
      amount: parseFloat(amount),
      actualTicketPrice: actualTicketPrice,
      paymentId,
      reason,
      status: 'pending', // pending, approved, rejected, processed
      showDate,
      movieTitle,
      theatreName,
      selectedSeats: selectedSeats || [],
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedAt: null,
      refundId: null,
      adminNotes: '',
      createdBy: 'user'
    };

    const refundDoc = await db.collection('refund_requests').add(refundRequest);
    
    // Get user details for notification
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const userName = userData.name || 'User';

    // Send notification to admin
    await sendNotificationToAdmin(
      'New Refund Request',
      `${userName} has requested a refund of ₹${amount} for movie booking cancellation`,
      {
        type: 'movie_refund_request',
        refundRequestId: refundDoc.id,
        bookingId,
        userId,
        amount: parseFloat(amount),
        userName,
        timestamp: new Date().toISOString(),
      }
    );

    // Update booking status to 'cancelled'
    await db.collection('movie_bookings').doc(bookingId).update({
      status: 'cancelled',
      refundRequestId: refundDoc.id,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp()
    });

    return { 
      success: true, 
      refundRequestId: refundDoc.id,
      message: 'BookMyBiz movie booking refund request submitted successfully. Admin will review and process your refund within 24-48 hours.'
    };

  } catch (error) {
    console.error('Error creating refund request:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// Function to process movie booking refund (admin approval)
exports.processMovieBookingRefund = functions.https.onCall(async (data, context) => {
  try {
    const { refundRequestId, action, adminNotes = '' } = data; // action: 'approve' or 'reject'
    
    if (!refundRequestId || !action) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
    }

    const db = admin.firestore();
    const refundDoc = await db.collection('refund_requests').doc(refundRequestId).get();
    
    if (!refundDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Refund request not found');
    }

    const refundData = refundDoc.data();
    
    if (refundData.status !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'Refund request already processed');
    }

    if (action === 'reject') {
      // Simply update status to rejected
      await refundDoc.ref.update({
        status: 'rejected',
        adminNotes,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // Notify user about rejection
      await sendNotificationToUser(refundData.userId, 
        'Refund Request Rejected',
        `Your refund request has been rejected. ${adminNotes || 'Please contact support for more details.'}`,
        {
          type: 'refund_rejected',
          refundRequestId,
          bookingId: refundData.bookingId
        }
      );

      return { success: true, message: 'Refund request rejected' };
    }

    if (action === 'approve') {
      // Process refund with theatre owner recovery
      const client = getRazorpayClient();
      const totalAmount = refundData.amount;
      
      try {
        // Calculate amounts
        const actualTicketPrice = refundData.actualTicketPrice || (totalAmount / 1.12); // Base ticket price (total/1.12)
        const platformAmount = totalAmount - actualTicketPrice;
        
        console.log(`Refund breakdown: Total=${totalAmount}, TicketPrice=${actualTicketPrice}, Platform=${platformAmount}`);
        
        // Step 1: Try to recover ticket amount from theatre owner
        let theatreOwnerRefunded = false;
        let theatreOwnerRefundId = null;
        
        try {
          // Get theatre owner's Razorpay account ID
          const theatreDoc = await db.collection('movie_theatres').doc(refundData.theatreId).get();
          if (theatreDoc.exists) {
            const theatreData = theatreDoc.data();
            const ownerId = theatreData.ownerId;
            
            if (ownerId) {
              const ownerDoc = await db.collection('users').doc(ownerId).get();
              if (ownerDoc.exists) {
                const ownerData = ownerDoc.data();
                const ownerAccountId = ownerData.razorpayAccountId;
                
                if (ownerAccountId && ownerAccountId.startsWith('acc_')) {
                  // Create a transfer from theatre owner to platform (reverse transfer)
                  const reverseTransfer = await client.transfers.create({
                    amount: Math.round(actualTicketPrice * 100), // Convert to paise
                    currency: 'INR',
                    source: ownerAccountId,
                    destination: 'acc_merchant', // Your merchant account
                    notes: {
                      purpose: 'Refund recovery for movie booking cancellation',
                      booking_id: refundData.bookingId,
                      refund_request_id: refundRequestId
                    }
                  });
                  
                  theatreOwnerRefunded = true;
                  theatreOwnerRefundId = reverseTransfer.id;
                  console.log(`Successfully recovered ₹${actualTicketPrice} from theatre owner`);
                }
              }
            }
          }
        } catch (theatreOwnerError) {
          console.error('Failed to recover from theatre owner:', theatreOwnerError);
          // Continue with platform-only refund
        }
        
        // Step 2: Process refund to user
        const refundAmount = Math.round(totalAmount * 100); // Full amount in paise
        const refund = await client.payment.refund(refundData.paymentId, {
          amount: refundAmount,
          notes: {
            reason: refundData.reason,
            booking_id: refundData.bookingId,
            refund_request_id: refundRequestId,
            admin_notes: adminNotes,
            theatre_owner_recovered: theatreOwnerRefunded,
            theatre_owner_refund_id: theatreOwnerRefundId
          }
        });

        // Update refund request with details
        await refundDoc.ref.update({
          status: 'processed',
          refundId: refund.id,
          razorpayRefundId: refund.id,
          refundStatus: refund.status,
          adminNotes,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          refundBreakdown: {
            totalAmount: totalAmount,
            actualTicketPrice: actualTicketPrice,
            platformAmount: platformAmount,
            theatreOwnerRecovered: theatreOwnerRefunded,
            theatreOwnerRefundId: theatreOwnerRefundId
          }
        });

        // Update booking status
        await db.collection('movie_bookings').doc(refundData.bookingId).update({
          refundStatus: 'processed',
          refundId: refund.id,
          refundedAt: admin.firestore.FieldValue.serverTimestamp(),
          refundBreakdown: {
            totalAmount: totalAmount,
            actualTicketPrice: actualTicketPrice,
            platformAmount: platformAmount,
            theatreOwnerRecovered: theatreOwnerRefunded
          }
        });

        // Notify user about successful refund
        const refundMessage = theatreOwnerRefunded 
          ? `Your refund of ₹${totalAmount} has been processed. Ticket amount (₹${actualTicketPrice}) recovered from theatre owner, platform fees (₹${platformAmount}) refunded by platform.`
          : `Your refund of ₹${totalAmount} has been processed and will reflect in your account within 5-7 business days.`;
          
        await sendNotificationToUser(refundData.userId,
          'Refund Processed Successfully',
          refundMessage,
          {
            type: 'movie_refund_processed',
            refundRequestId,
            bookingId: refundData.bookingId,
            amount: totalAmount,
            refundId: refund.id,
            theatreOwnerRecovered: theatreOwnerRefunded
          }
        );

        return { 
          success: true, 
          refundId: refund.id,
          message: 'Refund processed successfully',
          refundBreakdown: {
            totalAmount: totalAmount,
            actualTicketPrice: actualTicketPrice,
            platformAmount: platformAmount,
            theatreOwnerRecovered: theatreOwnerRefunded
          }
        };

      } catch (razorpayError) {
        console.error('Razorpay refund failed:', razorpayError);
        
        // Update status to failed
        await refundDoc.ref.update({
          status: 'failed',
          adminNotes: `Razorpay refund failed: ${razorpayError.message}`,
          processedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        throw new functions.https.HttpsError('internal', `Refund processing failed: ${razorpayError.message}`);
      }
    }

  } catch (error) {
    console.error('Error processing refund:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// Function to send notification to user
async function sendNotificationToUser(userId, title, body, data = {}) {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.log('User not found:', userId);
      return;
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;

    if (!fcmToken) {
      console.log('User FCM token not found:', userId);
      return;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: fcmToken,
      android: {
        notification: {
          channel_id: 'movie_refund_channel',
          priority: 'high',
          default_sound: true,
          default_vibrate_timings: true,
          icon: 'app',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log('Successfully sent notification to user:', response);
    return response;
  } catch (error) {
    console.error('Error sending notification to user:', error);
    throw error;
  }
}