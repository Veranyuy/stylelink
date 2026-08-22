import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/provider.dart';
import '../../services/supabase_service.dart';
import '../widgets/skeleton.dart';

/// Provider "List / Edit My Business" screen.
///
/// Creates or updates the provider's `public.providers` row: business name,
/// category, city, quarter, bio, service mode (Studio / Home) and a
/// day-by-day working-hours editor (stored as jsonb). The save upserts the
/// row for the signed-in user.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final supabase = SupabaseService.instance;

  static const _categories = [
    'Barbing / Coiffure',
    'Braiding / Tresses',
    'Nails / Ongles',
    'Makeup / Maquillage',
    'Massage',
  ];
  static const _cities = ['Douala', 'Yaoundé', 'Limbe', 'Bafoussam', 'Kribi'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Future<Provider?>? _providerFuture;
  bool _loading = false;

  final _name = TextEditingController();
  final _quarter = TextEditingController();
  final _bio = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  /// Newly picked photo (not yet uploaded) and its bytes for the preview.
  XFile? _coverFile;
  Uint8List? _coverBytes;

  /// The cover URL that will be saved: the provider's existing one loaded
  /// from the DB, the freshly uploaded URL once a new photo is saved, or
  /// null when the photo was removed.
  String? _coverUrl;

  String? _category;
  String? _city;
  ServiceType _serviceType = ServiceType.studio;
  Map<String, String?> _hours = {
    for (final d in _days) d: null,
  };

  @override
  void initState() {
    super.initState();
    _providerFuture = _load();
  }

  Future<Provider?> _load() async {
    final user = supabase.currentUser;
    if (user == null) return null;
    final provider = await supabase.fetchProviderByUserId(user.id);
    if (!mounted) return provider;
    setState(() {
      if (provider != null) {
        _name.text = provider.businessName;
        _category = provider.category;
        _city = provider.city;
        _quarter.text = provider.quarter ?? '';
        _bio.text = provider.bio ?? '';
        _coverUrl = provider.coverUrl;
        _serviceType = provider.serviceType;
        _hours = {
          for (final d in _days) d: provider.workingHours[d],
        };
      }
    });
    return provider;
  }

  @override
  void dispose() {
    _name.dispose();
    _quarter.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final category = _category;
    final city = _city;
    if (name.isEmpty || category == null || city == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Business name, category and city are required. / '
            'Nom, catégorie et ville sont requis.',
          ),
          backgroundColor: Color(0xFFB3261E),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // Upload the newly picked photo first; if it fails, the business row
      // is left untouched and the error surfaces in the catch below.
      var coverUrl = _coverUrl;
      if (_coverFile != null && _coverBytes != null) {
        coverUrl = await supabase.uploadProviderCover(_coverBytes!);
      }
      final existing = await _providerFuture;
      await supabase.saveBusiness(
        providerId: existing?.id,
        businessName: name,
        category: category,
        city: city,
        quarter: _quarter.text.trim().isEmpty ? null : _quarter.text.trim(),
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        serviceType: _serviceType,
        coverUrl: coverUrl,
        workingHours: _hours,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business saved / Entreprise enregistrée')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save business: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCover(ImageSource source) async {
    if (kIsWeb && source == ImageSource.camera) {
      _showSnack(
        'Camera is not available in the browser — choose from gallery. / '
        "La caméra n'est pas disponible dans le navigateur — choisissez dans "
        'la galerie.',
      );
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _coverFile = file;
        _coverBytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not open the photo picker: $e');
    }
  }

  Future<void> _changeCover() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take Photo / Prendre une photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title:
                  const Text('Choose from Gallery / Choisir dans la galerie'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel / Annuler'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickCover(source);
  }

  void _removeCover() {
    setState(() {
      _coverFile = null;
      _coverBytes = null;
      _coverUrl = null;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB3261E),
      ),
    );
  }

  Future<void> _pickTime(String day, {required bool isStart}) async {
    final current = _hours[day];
    final parts = current == null ? ['09:00', '19:00'] : current.split('-');
    final initial = TimeOfDay(
      hour: int.parse(parts[isStart ? 0 : 1].split(':')[0]),
      minute: int.parse(parts[isStart ? 0 : 1].split(':')[1]),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Open / Ouverture' : 'Close / Fermeture',
    );
    if (picked == null || !mounted) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    setState(() {
      final start = isStart ? '$hh:$mm' : (parts.isNotEmpty ? parts[0] : '09:00');
      final end = isStart ? (parts.length > 1 ? parts[1] : '19:00') : '$hh:$mm';
      _hours[day] = '$start-$end';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('List / Edit My Business'),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<Provider?>(
        future: _providerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: ListSkeleton(count: 4),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _field(
                _name,
                'Business / Professional Name',
                hint: 'e.g. Studio Akwa Barbing',
                required: true,
              ),
              const SizedBox(height: 16),
              _dropdown('Category / Catégorie', _category, _categories, (v) {
                setState(() => _category = v);
              }),
              const SizedBox(height: 16),
              _dropdown('City / Ville', _city, _cities, (v) {
                setState(() => _city = v);
              }),
              const SizedBox(height: 16),
              _field(
                _quarter,
                'Quarter / Neighborhood',
                hint: 'e.g. Bonapriso',
              ),
              const SizedBox(height: 16),
              _field(_bio, 'Bio / Description', maxLines: 3),
              const SizedBox(height: 16),
              _coverPicker(),
              const SizedBox(height: 20),
              const Text(
                'Service Mode / Mode de service',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SegmentedButton<ServiceType>(
                segments: const [
                  ButtonSegment(
                    value: ServiceType.studio,
                    label: Text('Studio'),
                    icon: Icon(Icons.storefront_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: ServiceType.home,
                    label: Text('Home'),
                    icon: Icon(Icons.home_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: ServiceType.both,
                    label: Text('Both'),
                    icon: Icon(Icons.home_work_outlined, size: 17),
                  ),
                ],
                selected: {_serviceType},
                onSelectionChanged: (s) =>
                    setState(() => _serviceType = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 22),
              const Text(
                'Working Hours / Horaires',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Toggle each day and set open/close times.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              for (final day in _days) _dayRow(day),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFFF4665C),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Business / Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Cover photo section: a preview card plus Take Photo / Choose from
  /// Gallery (or Change / Remove once a photo is set). The picked file is
  /// uploaded to Supabase Storage only when the form is saved.
  Widget _coverPicker() {
    final hasNew = _coverBytes != null;
    final current = hasNew ? null : _coverUrl;
    final hasImage = hasNew || current != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cover Photo / Photo de couverture',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          height: 180,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0x14F4665C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x14000000)),
          ),
          child:
              hasImage ? _coverPreview(hasNew, current) : _coverPlaceholder(),
        ),
        const SizedBox(height: 10),
        if (hasImage)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _changeCover,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Change / Changer'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    side: const BorderSide(color: Color(0x33000000)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  onPressed: _removeCover,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove / Supprimer'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: const Color(0xFFB3261E),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _pickCover(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Take Photo'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: const Color(0xFFF4665C),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _pickCover(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Choose from Gallery'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _coverPreview(bool hasNew, String? current) {
    if (hasNew) {
      return Image.memory(
        _coverBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Image.network(
      current!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _coverPlaceholder(),
    );
  }

  Widget _coverPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 6),
          Text(
            'No cover photo yet / Pas encore de photo de couverture',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _dayRow(String day) {
    final window = _hours[day];
    final open = window != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              day,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          Switch(
            value: open,
            activeTrackColor: const Color(0xFFF4665C),
            onChanged: (v) => setState(() {
              _hours[day] =
                  v ? (window ?? '09:00-19:00') : null;
            }),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: open
                ? Row(
                    children: [
                      _timeButton(day, isStart: true, label: window.split('-').first),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('–'),
                      ),
                      _timeButton(day, isStart: false, label: window.split('-').last),
                    ],
                  )
                : Text(
                    'Closed / Fermé',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timeButton(String day, {required bool isStart, required String label}) {
    return TextButton(
      onPressed: () => _pickTime(day, isStart: isStart),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 34),
        foregroundColor: const Color(0xFF2A2730),
        backgroundColor: const Color(0x14F4665C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Text(
        _to12h(label),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  static String _to12h(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]);
    if (h == null) return hhmm;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return parts[1] == '00' ? '$hour12 $suffix' : '$hour12:${parts[1]} $suffix';
  }
}
