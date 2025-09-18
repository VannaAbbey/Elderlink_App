import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class EditProfile extends StatefulWidget {
  const EditProfile({super.key});

  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  String? _profilePicUrl;
  final ImagePicker _picker = ImagePicker();
  bool isEditing = false;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fullNameController;
  late TextEditingController _birthdayController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  @override
  void initState() {
  _loadProfilePic();
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _fullNameController = TextEditingController(text: _getFullName(authProvider));
    _birthdayController = TextEditingController(text: _getBirthday(authProvider));
    _emailController = TextEditingController(text: authProvider.userEmail);
    _phoneController = TextEditingController(text: authProvider.userContactNum);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _birthdayController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfilePic() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      // UID not available yet, skip loading
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    setState(() {
      _profilePicUrl = doc.data()?['user_profilePic'] as String?;
    });
  }

  Future<void> _pickAndUploadImage() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID not available. Please try again later.'), backgroundColor: Color(0xFF00588e)),
      );
      return;
    }
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final storageRef = FirebaseStorage.instance.ref().child('user_profilePic/$uid.jpg');
      await storageRef.putData(await pickedFile.readAsBytes());
      final downloadUrl = await storageRef.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'user_profilePic': downloadUrl});
      setState(() {
        _profilePicUrl = downloadUrl;
      });
      // Refresh user data so sidebar avatar updates
      await authProvider.refreshUserData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Color(0xFF00588e)),
      );
    }
  }

  String _getFullName(AuthProvider authProvider) {
    final fname = authProvider.userFirstName;
    final lname = authProvider.userLastName;
    return (fname.isNotEmpty || lname.isNotEmpty) ? '$fname $lname' : '';
  }

  String _getBirthday(AuthProvider authProvider) {
    final userData = authProvider.userData;
    if (userData != null && userData['user_bday'] != null) {
      // Firestore stores as Timestamp, convert to string
      final bday = userData['user_bday'];
      if (bday is String) return bday;
      if (bday is DateTime) return '${bday.year}-${bday.month}-${bday.day}';
      if (bday.toString().contains('Timestamp')) {
        // Try to parse Timestamp
        try {
          final date = bday.toDate();
          return '${date.year}-${date.month}-${date.day}';
        } catch (_) {}
      }
    }
    return '';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00588e)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Profile', style: TextStyle(color: Color(0xFF00588e), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                final uid = authProvider.currentUser?.uid ?? '';
                // Show loading indicator until UID and user data are available
                if (uid.isEmpty || authProvider.userEmail.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF00588e)),
                        const SizedBox(height: 16),
                        const Text('Loading profile...', style: TextStyle(color: Color(0xFF00588e))),
                      ],
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      height: constraints.maxHeight,
                      width: constraints.maxWidth,
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                const SizedBox(height: 16),
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 100,
                                      backgroundImage: (_profilePicUrl != null && _profilePicUrl!.isNotEmpty)
                                        ? NetworkImage(_profilePicUrl!)
                                        : AssetImage('assets/images/people_icon.png') as ImageProvider,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: _pickAndUploadImage,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          child: const Icon(Icons.camera_alt, color: Color(0xFF00588e)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 30),
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: Text(
                                            'Nurse ${authProvider.userFirstName}',
                                            style: TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF00588e),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 30),
                                        Form(
                                          key: _formKey,
                                          child: Column(
                                            children: [
                                              _profileField(
                                                icon: Icons.person,
                                                label: 'Full Name',
                                                controller: _fullNameController,
                                                enabled: isEditing,
                                              ),
                                              const SizedBox(height: 18),
                                              _profileField(
                                                icon: Icons.cake,
                                                label: 'Birthday',
                                                controller: _birthdayController,
                                                enabled: isEditing,
                                              ),
                                              const SizedBox(height: 18),
                                              _profileField(
                                                icon: Icons.email,
                                                label: 'Email',
                                                controller: _emailController,
                                                enabled: isEditing,
                                              ),
                                              const SizedBox(height: 18),
                                              _profileField(
                                                icon: Icons.phone,
                                                label: 'Phone Number',
                                                controller: _phoneController,
                                                enabled: isEditing,
                                              ),
                                              const SizedBox(height: 20),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  icon: Icon(Icons.edit),
                                                  label: Text('Edit Profile'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Color(0xFF00588e),
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                  ),
                                                  onPressed: () {
                                                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                                    final bottomSheetFirstNameController = TextEditingController(text: authProvider.userFirstName);
                                                    final bottomSheetLastNameController = TextEditingController(text: authProvider.userLastName);
                                                    final bottomSheetBirthdayController = TextEditingController(text: _birthdayController.text);
                                                    final bottomSheetEmailController = TextEditingController(text: _emailController.text);
                                                    final bottomSheetPhoneController = TextEditingController(text: _phoneController.text);
                                                    final bottomSheetFormKey = GlobalKey<FormState>();
                                                    showModalBottomSheet(
                                                      context: context,
                                                      isScrollControlled: true,
                                                      shape: const RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                                      ),
                                                      builder: (context) {
                                                        return Padding(
                                                          padding: EdgeInsets.only(
                                                            bottom: MediaQuery.of(context).viewInsets.bottom,
                                                            left: 16,
                                                            right: 16,
                                                            top: 24,
                                                          ),
                                                          child: Form(
                                                            key: bottomSheetFormKey,
                                                            child: Column(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                                                const SizedBox(height: 30),
                                                                Row(
                                                                  children: [
                                                                    Expanded(
                                                                      child: Column(
                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                        children: [
                                                                          const Text('First Name', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00588e))),
                                                                          const SizedBox(height: 6),
                                                                          TextFormField(
                                                                            controller: bottomSheetFirstNameController,
                                                                            decoration: const InputDecoration(
                                                                              border: OutlineInputBorder(
                                                                                borderRadius: BorderRadius.all(Radius.circular(15)),
                                                                              ),
                                                                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                            ),
                                                                            validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 16),
                                                                    Expanded(
                                                                      child: Column(
                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                        children: [
                                                                          const Text('Last Name', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00588e))),
                                                                          const SizedBox(height: 6),
                                                                          TextFormField(
                                                                            controller: bottomSheetLastNameController,
                                                                            decoration: const InputDecoration(
                                                                              border: OutlineInputBorder(
                                                                                borderRadius: BorderRadius.all(Radius.circular(15)),
                                                                              ),
                                                                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                            ),
                                                                            validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 18),
                                                                Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    const Text('Birthday', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00588e))),
                                                                    const SizedBox(height: 6),
                                                                    GestureDetector(
                                                                      onTap: () async {
                                                                        DateTime? pickedDate = await showDatePicker(
                                                                          context: context,
                                                                          initialDate: DateTime.tryParse(bottomSheetBirthdayController.text) ?? DateTime(2000, 1, 1),
                                                                          firstDate: DateTime(1900),
                                                                          lastDate: DateTime.now(),
                                                                        );
                                                                        if (pickedDate != null) {
                                                                          bottomSheetBirthdayController.text = "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
                                                                        }
                                                                      },
                                                                      child: AbsorbPointer(
                                                                        child: TextFormField(
                                                                          controller: bottomSheetBirthdayController,
                                                                          decoration: const InputDecoration(
                                                                            border: OutlineInputBorder(
                                                                              borderRadius: BorderRadius.all(Radius.circular(15)),
                                                                            ),
                                                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                          ),
                                                                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 18),
                                                                Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    const Text('Email', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00588e))),
                                                                    const SizedBox(height: 6),
                                                                    TextFormField(
                                                                      controller: bottomSheetEmailController,
                                                                      enabled: false,
                                                                      decoration: const InputDecoration(
                                                                        border: OutlineInputBorder(
                                                                          borderRadius: BorderRadius.all(Radius.circular(15)),
                                                                        ),
                                                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 15),
                                                                Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    const Text('Phone Number', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00588e))),
                                                                    const SizedBox(height: 5),
                                                                    TextFormField(
                                                                      controller: bottomSheetPhoneController,
                                                                      decoration: const InputDecoration(
                                                                        border: OutlineInputBorder(
                                                                          borderRadius: BorderRadius.all(Radius.circular(15)),
                                                                        ),
                                                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                                      ),
                                                                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 24),
                                                                Row(
                                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                                  children: [
                                                                    TextButton(
                                                                      onPressed: () => Navigator.of(context).pop(),
                                                                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF00588e))),
                                                                    ),
                                                                    ElevatedButton(
                                                                      onPressed: () async {
                                                                        if (bottomSheetFormKey.currentState!.validate()) {
                                                                          setState(() {
                                                                            _fullNameController.text = "${bottomSheetFirstNameController.text} ${bottomSheetLastNameController.text}";
                                                                            _birthdayController.text = bottomSheetBirthdayController.text;
                                                                            _emailController.text = bottomSheetEmailController.text;
                                                                            _phoneController.text = bottomSheetPhoneController.text;
                                                                          });
                                                                          // Save using split names
                                                                          await authProvider.updateUserProfile({
                                                                            'user_fname': bottomSheetFirstNameController.text,
                                                                            'user_lname': bottomSheetLastNameController.text,
                                                                            'user_bday': bottomSheetBirthdayController.text,
                                                                            'user_email': bottomSheetEmailController.text,
                                                                            'user_contactNum': bottomSheetPhoneController.text,
                                                                          });
                                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                                            const SnackBar(
                                                                              content: Text('Profile updated!'),
                                                                              backgroundColor: Color(0xFF00588e),
                                                                            ),
                                                                          );
                                                                          Navigator.of(context).pop();
                                                                        }
                                                                      },
                                                                      child: const Text('Save Changes',
                                                                      style: TextStyle(
                                                                        fontSize: 16, 
                                                                        fontWeight: 
                                                                        FontWeight.bold, 
                                                                        color: Color(0xFF00588e)),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 10),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  },
                                                ),
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
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _profileField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
    if (!enabled) {
      // Read-only display
      String displayText = controller.text;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Color(0xFF1D5B78), size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayText,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Editable field
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: Color(0xFF00588e)),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: label,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
            ),
          ],
        ),
      );
    }
  }
}
