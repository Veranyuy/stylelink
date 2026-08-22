import 'package:flutter/material.dart';

import '../../models/provider.dart';
import '../../models/service.dart';
import '../../services/supabase_service.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Provider Services tab: full CRUD over the provider's `public.services`
/// catalog. Requires an existing provider row (create one via the business
/// management screen first).
class ServiceManagerScreen extends StatefulWidget {
  const ServiceManagerScreen({super.key});

  @override
  State<ServiceManagerScreen> createState() => _ServiceManagerScreenState();
}

class _ServiceManagerScreenState extends State<ServiceManagerScreen> {
  final supabase = SupabaseService.instance;

  Future<Provider?>? _providerFuture;
  Future<List<Service>>? _servicesFuture;

  @override
  void initState() {
    super.initState();
    _providerFuture = _resolveProvider();
  }

  Future<Provider?> _resolveProvider() async {
    final user = supabase.currentUser;
    if (user == null) return null;
    final provider = await supabase.fetchProviderByUserId(user.id);
    if (!mounted) return provider;
    setState(() {
      _servicesFuture = provider == null
          ? Future.value(const <Service>[])
          : supabase.fetchServicesForProvider(provider.id);
    });
    return provider;
  }

  void _reloadServices(String providerId) {
    setState(() {
      _servicesFuture = supabase.fetchServicesForProvider(providerId);
    });
  }

  Future<void> _openServiceDialog({Service? existing}) async {
    final providerId = (await _providerFuture)?.id;
    if (!mounted) return;
    if (providerId == null) return;
    final controllerName = TextEditingController(text: existing?.name ?? '');
    final controllerPrice =
        TextEditingController(text: existing?.price.toString() ?? '');
    final controllerDuration =
        TextEditingController(text: existing?.durationMinutes.toString() ?? '30');
    final controllerDescription =
        TextEditingController(text: existing?.description ?? '');
    var isActive = existing?.isActive ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Service / Ajouter' : 'Edit Service / Modifier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controllerName,
                  decoration: const InputDecoration(
                    labelText: 'Service name / Nom',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controllerPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price (FCFA) / Prix',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controllerDuration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (minutes) / Durée',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controllerDescription,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active / Actif'),
                  value: isActive,
                  onChanged: (v) =>
                      setDialogState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel / Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF4665C),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save / Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    final name = controllerName.text.trim();
    final price = int.tryParse(controllerPrice.text.trim());
    final duration = int.tryParse(controllerDuration.text.trim());
    if (name.isEmpty || price == null || duration == null || duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in a name, valid price and duration. / '
            'Veuillez remplir les champs.',
          ),
          backgroundColor: Color(0xFFB3261E),
        ),
      );
      return;
    }

    try {
      if (existing == null) {
        await supabase.createService(
          providerId: providerId,
          name: name,
          price: price,
          durationMinutes: duration,
          description:
              controllerDescription.text.trim().isEmpty
                  ? null
                  : controllerDescription.text.trim(),
        );
      } else {
        await supabase.updateService(
          Service(
            id: existing.id,
            providerId: existing.providerId,
            name: name,
            description:
                controllerDescription.text.trim().isEmpty
                    ? null
                    : controllerDescription.text.trim(),
            price: price,
            durationMinutes: duration,
            isActive: isActive,
            createdAt: existing.createdAt,
          ),
        );
      }
      _reloadServices(providerId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save service: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  Future<void> _deleteService(Service service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text('Remove "${service.name}" from your catalog?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel / Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete / Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await supabase.deleteService(service.id);
      final providerId = (await _providerFuture)?.id;
      if (providerId != null) _reloadServices(providerId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete service: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Services / Mes Prestations',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                ),
                FutureBuilder<Provider?>(
                  future: _providerFuture,
                  builder: (context, snapshot) => IconButton.filled(
                    onPressed: snapshot.data == null ? null : _openServiceDialog,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF4665C),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add),
                    tooltip: 'Add service',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Provider?>(
              future: _providerFuture,
              builder: (context, providerSnapshot) {
                if (providerSnapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: ListSkeleton(count: 3),
                  );
                }
                if (providerSnapshot.data == null) {
                  return const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No business yet',
                    subtitle:
                        'Create your business from the Profile tab to start '
                        'adding services.\n'
                        "Créez votre entreprise depuis l'onglet Profil.",
                  );
                }
                return FutureBuilder<List<Service>>(
                  future: _servicesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: ListSkeleton(count: 3),
                      );
                    }
                    if (snapshot.hasError) {
                      return ErrorRetry(
                        message: 'Could not load services.\n${snapshot.error}',
                        onRetry: () => _reloadServices(
                          providerSnapshot.data!.id,
                        ),
                      );
                    }
                    final services = snapshot.data ?? const <Service>[];
                    if (services.isEmpty) {
                      return const EmptyState(
                        icon: Icons.content_cut_outlined,
                        title: 'No services yet',
                        subtitle:
                            'Tap + to add your first service listing.\n'
                            'Ajoutez votre première prestation.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: services.length,
                      itemBuilder: (context, i) {
                        final service = services[i];
                        return _ServiceRow(
                          service: service,
                          onEdit: () => _openServiceDialog(existing: service),
                          onDelete: () => _deleteService(service),
                        );
                      },
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
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.onEdit,
    required this.onDelete,
  });

  final Service service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x14000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          service.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!service.isActive) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x14A6A1AF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Off',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A8591),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${service.durationLabel} · ${service.priceLabel}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20,
                  color: Color(0xFFE5484D)),
            ),
          ],
        ),
      ),
    );
  }
}
