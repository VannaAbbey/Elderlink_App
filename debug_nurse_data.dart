import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  // Sign in anonymously for testing
  await auth.signInAnonymously();

  final user = auth.currentUser;
  if (user == null) {
    print('❌ No user signed in');
    return;
  }

  print('✅ Current user: ${user.uid}');

  // Check vitals
  print('\n🔍 Checking vitals collection...');
  final vitalsQuery = await firestore
      .collection('vitals')
      .where('status', isEqualTo: 'pending')
      .limit(10)
      .get();

  print('⚡ Found ${vitalsQuery.docs.length} pending vitals');

  for (final doc in vitalsQuery.docs) {
    final data = doc.data();
    print(
      '⚡ Vital ${doc.id}: elderly=${data['elderly_id']}, nurse=${data['assigned_nurse_id']}, shift=${data['shift']}, house=${data['house_id']}',
    );
  }

  // Check elderly assignments for current user
  print('\n🔍 Checking elderly assignments for current user...');
  final assignmentsQuery = await firestore
      .collection('elderly_assignments')
      .where('user_id', isEqualTo: user.uid)
      .where('is_current', isEqualTo: true)
      .get();

  print(
    '👴 Found ${assignmentsQuery.docs.length} assignments for current user',
  );

  for (final doc in assignmentsQuery.docs) {
    final data = doc.data();
    print('👴 Assignment ${doc.id}: ${data}');
  }
}
