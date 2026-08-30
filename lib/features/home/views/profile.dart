import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whatsapp_clone/shared/models/user.dart';
import 'package:whatsapp_clone/shared/repositories/compression_service.dart';
import 'package:whatsapp_clone/shared/repositories/firebase_storage.dart';
import 'package:whatsapp_clone/shared/repositories/isar_db.dart';
import 'package:whatsapp_clone/shared/repositories/r2_storage.dart';
import 'package:whatsapp_clone/shared/utils/attachment_utils.dart';
import 'package:whatsapp_clone/shared/utils/shared_pref.dart';
import 'package:whatsapp_clone/shared/utils/snackbars.dart';
import 'package:whatsapp_clone/shared/widgets/gallery.dart';
import 'package:whatsapp_clone/theme/theme.dart';

class ProfilePage extends ConsumerStatefulWidget {
  final User user;
  final Function(User updatedUser)? onProfileUpdated;

  const ProfilePage({
    super.key,
    required this.user,
    this.onProfileUpdated,
  });

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late User _currentUser;
  bool _isUploading = false;
  String _aboutText = 'Hey there! I am using KatsChat.';

  @override
  void initState() {
    _currentUser = widget.user;
    _aboutText = SharedPref.instance.getString('user_about') ??
        'Hey there! I am using KatsChat.';
    super.initState();
  }

  Future<void> _updateUserProfile(User newUser) async {
    setState(() {
      _currentUser = newUser;
    });

    // 1. Update SharedPreferences
    await SharedPref.instance
        .setString('user', jsonEncode(newUser.toMap()));

    // 2. Update Firestore
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUser.id)
          .update(newUser.toMap());
    } catch (e) {
      debugPrint('Error updating Firestore user: $e');
    }

    // 3. Update Isar DB
    try {
      await IsarDb.isar.writeTxn(() async {
        await IsarDb.isar.users.put(newUser);
      });
    } catch (e) {
      debugPrint('Error updating Isar user: $e');
    }

    widget.onProfileUpdated?.call(newUser);
  }

  Future<void> _uploadAvatar(File imageFile) async {
    setState(() {
      _isUploading = true;
    });

    try {
      final compressed = await CompressionService.compressImage(imageFile);
      final uid = _currentUser.id;
      final ext = compressed.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String newAvatarUrl = '';

      // Try R2 first
      try {
        newAvatarUrl = await R2StorageService.uploadFile(
          file: compressed,
          path: 'userAvatars/$uid-$timestamp.$ext',
        );
      } catch (e) {
        debugPrint('R2 Avatar upload failed, falling back to Firebase: $e');
        final task = await ref
            .read(firebaseStorageRepoProvider)
            .uploadFileToFirebase(compressed, 'userAvatars/$uid-$timestamp');
        newAvatarUrl = await (await task).ref.getDownloadURL();
      }

      if (newAvatarUrl.isNotEmpty) {
        final updatedUser = _currentUser.copyWith(avatarUrl: newAvatarUrl);
        await _updateUserProfile(updatedUser);
        if (mounted) {
          showSuccessNotification(
            context: context,
            message: 'Profile photo updated successfully!',
          );
        }
      }
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (mounted) {
        showErrorNotification(
          context: context,
          message: 'Failed to update profile photo. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showImagePickerOptions() {
    final colorTheme = Theme.of(context).custom.colorTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorTheme.appBarColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorTheme.textColor1,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPickerOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: colorTheme.greenColor,
                    onTap: () async {
                      Navigator.pop(bottomSheetContext);
                      final photo = await capturePhoto();
                      if (photo != null) {
                        await _uploadAvatar(photo);
                      }
                    },
                  ),
                  _buildPickerOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: colorTheme.blueColor,
                    onTap: () async {
                      Navigator.pop(bottomSheetContext);
                      if (Platform.isAndroid) {
                        final file = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const Gallery(
                              title: 'Pick a photo',
                              returnFiles: true,
                            ),
                            settings: const RouteSettings(name: '/gallery'),
                          ),
                        );
                        if (file != null) {
                          await _uploadAvatar(file);
                        }
                      } else {
                        final image = await pickImageFromGallery();
                        if (image != null) {
                          await _uploadAvatar(image);
                        }
                      }
                    },
                  ),
                  if (_currentUser.avatarUrl.isNotEmpty &&
                      !_currentUser.avatarUrl.contains('default'))
                    _buildPickerOption(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
                      color: Colors.red,
                      onTap: () async {
                        Navigator.pop(bottomSheetContext);
                        const defaultUrl =
                            'https://en.gravatar.com/userimage/238463648/8cc16f6f5423605920569a634fd097eb.jpeg?size=256';
                        final updated =
                            _currentUser.copyWith(avatarUrl: defaultUrl);
                        await _updateUserProfile(updated);
                        if (mounted) {
                          showSuccessNotification(
                            context: context,
                            message: 'Profile photo removed',
                          );
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colorTheme = Theme.of(context).custom.colorTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: colorTheme.textColor1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog() {
    final textController = TextEditingController(text: _currentUser.name);
    final colorTheme = Theme.of(context).custom.colorTheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colorTheme.appBarColor,
        title: Text(
          'Enter your name',
          style: TextStyle(color: colorTheme.textColor1),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(color: colorTheme.textColor1),
          decoration: InputDecoration(
            hintText: 'Your name',
            hintStyle: TextStyle(color: colorTheme.greyColor),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorTheme.greenColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorTheme.greenColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('CANCEL', style: TextStyle(color: colorTheme.greyColor)),
          ),
          TextButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(dialogContext);
                final updatedUser = _currentUser.copyWith(name: newName);
                await _updateUserProfile(updatedUser);
              }
            },
            child: Text('SAVE', style: TextStyle(color: colorTheme.greenColor)),
          ),
        ],
      ),
    );
  }

  void _showEditAboutDialog() {
    final textController = TextEditingController(text: _aboutText);
    final colorTheme = Theme.of(context).custom.colorTheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colorTheme.appBarColor,
        title: Text(
          'About / Status',
          style: TextStyle(color: colorTheme.textColor1),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(color: colorTheme.textColor1),
          decoration: InputDecoration(
            hintText: 'Add an about note',
            hintStyle: TextStyle(color: colorTheme.greyColor),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorTheme.greenColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorTheme.greenColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('CANCEL', style: TextStyle(color: colorTheme.greyColor)),
          ),
          TextButton(
            onPressed: () async {
              final newAbout = textController.text.trim();
              if (newAbout.isNotEmpty) {
                Navigator.pop(dialogContext);
                setState(() {
                  _aboutText = newAbout;
                });
                await SharedPref.instance.setString('user_about', newAbout);
              }
            },
            child: Text('SAVE', style: TextStyle(color: colorTheme.greenColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = Theme.of(context).custom.colorTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _currentUser),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 70,
                  backgroundColor: colorTheme.appBarColor,
                  backgroundImage: CachedNetworkImageProvider(
                    _currentUser.avatarUrl,
                  ),
                  child: _isUploading
                      ? Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: colorTheme.greenColor,
                            ),
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 4,
                  child: InkWell(
                    onTap: _isUploading ? null : _showImagePickerOptions,
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: colorTheme.greenColor,
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: Icon(Icons.person_outline, color: colorTheme.greenColor),
            title: Text(
              'Name',
              style: TextStyle(fontSize: 13, color: colorTheme.greyColor),
            ),
            subtitle: Text(
              _currentUser.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorTheme.textColor1,
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.edit, color: colorTheme.greenColor, size: 20),
              onPressed: _showEditNameDialog,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 72.0),
            child: Text(
              'This is not your username or pin. This name will be visible to your KatsChat contacts.',
              style: TextStyle(fontSize: 12, color: colorTheme.greyColor),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(indent: 72),
          ListTile(
            leading: Icon(Icons.info_outline, color: colorTheme.greenColor),
            title: Text(
              'About',
              style: TextStyle(fontSize: 13, color: colorTheme.greyColor),
            ),
            subtitle: Text(
              _aboutText,
              style: TextStyle(
                fontSize: 15,
                color: colorTheme.textColor1,
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.edit, color: colorTheme.greenColor, size: 20),
              onPressed: _showEditAboutDialog,
            ),
          ),
          const Divider(indent: 72),
          ListTile(
            leading: Icon(Icons.phone_outlined, color: colorTheme.greenColor),
            title: Text(
              'Phone',
              style: TextStyle(fontSize: 13, color: colorTheme.greyColor),
            ),
            subtitle: Text(
              _currentUser.phone.getFormattedNumber(),
              style: TextStyle(
                fontSize: 15,
                color: colorTheme.textColor1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
