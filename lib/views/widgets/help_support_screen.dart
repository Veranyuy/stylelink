import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../main.dart' show ThemeScopeExtension;
import '../../providers/language_provider.dart';
import '../../utils/legal_text.dart';

/// Full-screen Help & Support page with three sections:
///   1. FAQ (expandable accordion)
///   2. Help & Support (contact options)
///   3. Terms of Service & Privacy Policy
///
/// Used by both client and provider profile screens.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final lang = context.lang;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          lang.isFrench ? 'Aide & Support' : 'Help & Support',
        ),
        centerTitle: false,
        backgroundColor: theme.scaffoldBackground,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── FAQ Section ────────────────────────────────────
          _SectionHeader(
            icon: Icons.help_outline_rounded,
            title: lang.isFrench ? 'Questions Fréquentes' : 'FAQ',
          ),
          const SizedBox(height: 10),
          ..._faqItems(lang).map((item) => _FaqTile(
                question: item.$1,
                answer: item.$2,
              )),

          const SizedBox(height: 28),

          // ── Help & Support Section ─────────────────────────
          _SectionHeader(
            icon: Icons.support_agent_rounded,
            title: lang.isFrench ? 'Nous Contacter' : 'Help & Support',
          ),
          const SizedBox(height: 10),
          _ContactCard(
            icon: Icons.email_outlined,
            title: 'Email Support',
            subtitle: 'support@stylelink.app',
            onTap: () => _launchEmail(context),
          ),

          const SizedBox(height: 28),

          // ── Legal Section ──────────────────────────────────
          _SectionHeader(
            icon: Icons.gavel_rounded,
            title: lang.isFrench ? 'Légal' : 'Legal',
          ),
          const SizedBox(height: 10),
          _LegalTile(
            title: lang.isFrench
                ? 'Conditions d\'Utilisation'
                : 'Terms of Service',
            content: _termsOfService(lang),
          ),
          const SizedBox(height: 8),
          _LegalTile(
            title: lang.isFrench
                ? 'Politique de Confidentialité'
                : 'Privacy Policy',
            content: _privacyPolicy(lang),
          ),

          const SizedBox(height: 20),

          // ── App version ────────────────────────────────────
          Center(
            child: Text(
              'StyleLink v1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: theme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@stylelink.app',
      queryParameters: {
        'subject': 'StyleLink Support Request',
      },
    );
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email client')),
        );
      }
    }
  }

  // ── FAQ content ──────────────────────────────────────────

  List<(String, String)> _faqItems(LanguageProvider lang) {
    if (lang.isFrench) {
      return [
        (
          'Comment réserver un rendez-vous ?',
          'Parcourez les prestataires, sélectionnez le service souhaité, '
              'choisissez une date et heure disponibles, puis confirmez votre '
              'réservation. Vous recevrez une confirmation par notification.',
        ),
        (
          'Comment annuler ou reprogrammer ?',
          'Allez dans l\'onglet "Rendez-vous", sélectionnez la réservation '
              'concernée, puis appuyez sur "Annuler" ou "Reprogrammer". '
              'Les conditions d\'annulation sont fixées par le prestataire ; '
              'contactez-le ou écrivez à support@stylelink.app en cas de litige.',
        ),
        (
          'Comment devenir prestataire ?',
          'Allez dans votre profil et appuyez sur "Devenir Prestataire". '
              'Remplissez les informations de votre entreprise, définissez vos '
              'heures d\'ouverture et ajoutez vos services. Votre compte sera '
              'activé immédiatement.',
        ),
        (
          'Comment laisser un avis ?',
          'Après qu\'un service soit marqué comme terminé, vous verrez un bouton '
              '"Évaluer" dans votre historique de réservations. Donnez une note '
              'et laissez un commentaire pour aider les autres clients.',
        ),
        (
          'Mes données sont-elles sécurisées ?',
          'Les échanges sont chiffrés en transit (HTTPS/TLS). L\'accès aux '
              'données est limité par des règles de sécurité au niveau des '
              'lignes (RLS) dans Supabase. Nous ne vendons pas vos données.',
        ),
        (
          'Comment signaler un prestataire ?',
          'Ouvrez le profil du prestataire, appuyez sur le menu (⋮), '
              'sélectionnez "Signaler" et choisissez la raison. '
              'Nous examinerons le signalement sous 48 heures.',
        ),
      ];
    }
    return [
      (
        'How do I book an appointment?',
        'Browse providers, select the service you want, pick an available '
            'date and time, then confirm your booking. You\'ll receive a '
            'confirmation notification.',
      ),
      (
        'How do I cancel or reschedule?',
        'Go to the "Appointments" tab, select the booking, then tap '
            '"Cancel" or "Reschedule". The provider sets their cancellation '
            'terms; contact them or support@stylelink.app if there is a dispute.',
      ),
      (
        'How do I become a provider?',
        'Go to your profile and tap "Become a Provider". Fill in your '
            'business details, set your working hours, and add your services. '
            'Your account will be activated immediately.',
      ),
      (
        'How do I leave a review?',
        'After a service is marked as completed, you\'ll see a "Rate" button '
            'in your booking history. Give a rating and leave a comment to '
            'help other clients.',
      ),
      (
        'Is my data secure?',
        'Traffic is encrypted in transit (HTTPS/TLS), and row-level security '
            '(RLS) policies limit access to the data you are allowed to see. '
            'We do not sell your data.',
      ),
      (
        'How do I report a provider?',
        'Open the provider\'s profile, tap the menu (⋮), select "Report", '
            'and choose a reason. We\'ll review the report within 48 hours.',
      ),
    ];
  }

  // ── Terms of Service ─────────────────────────────────────

  String _termsOfService(LanguageProvider lang) =>
      LegalText.terms(french: lang.isFrench);

  // ── Privacy Policy ───────────────────────────────────────

  String _privacyPolicy(LanguageProvider lang) =>
      LegalText.privacy(french: lang.isFrench);
}

// =============================================================================
// Section header
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFF4665C)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// FAQ tile (expandable)
// =============================================================================

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded ? const Color(0x22F4665C) : theme.divider,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                widget.answer,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.textSecondary,
                ),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Contact card
// =============================================================================

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0x149E86E6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF9E86E6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Legal tile (expandable full-text)
// =============================================================================

class _LegalTile extends StatefulWidget {
  const _LegalTile({required this.title, required this.content});

  final String title;
  final String content;

  @override
  State<_LegalTile> createState() => _LegalTileState();
}

class _LegalTileState extends State<_LegalTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: const Color(0xFFF4665C),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SingleChildScrollView(
                child: Text(
                  widget.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: theme.textSecondary,
                  ),
                ),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
