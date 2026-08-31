import 'package:flutter/material.dart';

import '../../main.dart' show ThemeScopeExtension;
import '../../models/profile.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';

/// Full-screen form for editing a user's profile (name, phone, city).
///
/// Used by both client and provider profile screens.  The screen loads the
/// current profile on init, pre-fills the form, and calls
/// [SupabaseService.updateProfile] on save.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  Profile? _profile;

  static const _cities = [
    'Douala',
    'Yaoundé',
    'Limbe',
    'Bafoussam',
    'Kribi',
    'Buea',
    'Bamenda',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.instance.fetchCurrentProfile();
    if (!mounted) return;
    if (profile != null) {
      _nameCtrl.text = profile.fullName ?? '';
      _phoneCtrl.text = profile.phoneNumber ?? '';
      _cityCtrl.text = profile.city ?? '';
    }
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = await SupabaseService.instance.updateProfile(
        fullName: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update profile: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final lang = context.lang;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          lang.isFrench ? 'Modifier le profil' : 'Edit Profile',
        ),
        centerTitle: false,
        backgroundColor: theme.scaffoldBackground,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                // ── Avatar preview ─────────────────────────────
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFF9E86E6),
                        backgroundImage: _profile?.avatarUrl != null &&
                                _profile!.avatarUrl!.isNotEmpty
                            ? NetworkImage(_profile!.avatarUrl!)
                            : null,
                        child: _profile?.avatarUrl == null ||
                                _profile!.avatarUrl!.isEmpty
                            ? Text(
                                _profile?.initials ?? '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF4665C),
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _profile?.email ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Form ──────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Full Name
                      _buildField(
                        controller: _nameCtrl,
                        label: lang.isFrench ? 'Nom complet' : 'Full Name',
                        icon: Icons.person_outline_rounded,
                        theme: theme,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? (lang.isFrench ? 'Requis' : 'Required')
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Phone Number
                      _buildField(
                        controller: _phoneCtrl,
                        label: lang.isFrench
                            ? 'Numéro de téléphone'
                            : 'Phone Number',
                        icon: Icons.phone_outlined,
                        theme: theme,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      // City dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _cityCtrl.text.isEmpty
                            ? null
                            : _cityCtrl.text,
                        decoration: _inputDecoration(
                          lang.isFrench ? 'Ville' : 'City',
                          Icons.location_city_outlined,
                          theme,
                        ),
                        items: _cities
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => _cityCtrl.text = v ?? '',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Save Button ───────────────────────────────
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF4665C),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          lang.isFrench ? 'Enregistrer' : 'Save Changes',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required dynamic theme,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label, icon, theme),
      validator: validator,
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
    dynamic theme,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF9E86E6)),
      filled: true,
      fillColor: theme.cardBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF4665C), width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
