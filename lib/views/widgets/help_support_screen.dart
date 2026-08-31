import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../main.dart' show ThemeScopeExtension;
import '../../providers/language_provider.dart';

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
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.phone_outlined,
            title: lang.isFrench ? 'Téléphone' : 'Phone',
            subtitle: '+237 6XX XXX XXX',
            onTap: () => _launchPhone(context),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.chat_bubble_outline,
            title: lang.isFrench ? 'Chat en Direct' : 'Live Chat',
            subtitle: lang.isFrench
                ? 'Disponible lun-ven, 9h-18h'
                : 'Available Mon–Fri, 9 AM – 6 PM',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    lang.isFrench
                        ? 'Chat en direct bientôt disponible'
                        : 'Live chat coming soon',
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 28),

          // ── Legal Section ──────────────────────────────────
          _SectionHeader(
            icon: Icons.gavel_rounded,
            title: lang.isFrench ? 'Légal' : 'Legal',
          ),
          const SizedBox(height: 10),
          _LegalTile(
            title: lang.isFrench ? 'Conditions d\'Utilisation' : 'Terms of Service',
            content: _termsOfService(lang),
          ),
          const SizedBox(height: 8),
          _LegalTile(
            title: lang.isFrench ? 'Politique de Confidentialité' : 'Privacy Policy',
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

  Future<void> _launchPhone(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: '+237600000000');
    if (await launcher.canLaunchUrl(uri)) {
      await launcher.launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer')),
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
              'Les annulations sont gratuites jusqu\'à 24h avant le rendez-vous.',
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
          'Oui. Nous utilisons Supabase avec chiffrement de bout en bout et '
              'des politiques de sécurité au niveau des lignes (RLS). Vos données '
              'personnelles ne sont jamais partagées sans votre consentement.',
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
            '"Cancel" or "Reschedule". Cancellations are free up to 24 hours '
            'before the appointment.',
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
        'Yes. We use Supabase with end-to-end encryption and row-level '
            'security (RLS) policies. Your personal data is never shared '
            'without your consent.',
      ),
      (
        'How do I report a provider?',
        'Open the provider\'s profile, tap the menu (⋮), select "Report", '
            'and choose a reason. We\'ll review the report within 48 hours.',
      ),
    ];
  }

  // ── Terms of Service ─────────────────────────────────────

  String _termsOfService(LanguageProvider lang) {
    if (lang.isFrench) {
      return '''
CONDITIONS D'UTILISATION — STYLELINK

Dernière mise à jour : 31 août 2026

1. ACCEPTATION DES CONDITIONS
En utilisant StyleLink ("l'Application"), vous acceptez ces conditions d'utilisation. Si vous n'acceptez pas ces conditions, veuillez ne pas utiliser l'Application.

2. DESCRIPTION DU SERVICE
StyleLink est une plateforme de mise en relation entre clients et prestataires de services de beauté et de coiffure au Cameroun. L'Application permet aux clients de rechercher, réserver et payer des services, et aux prestataires de gérer leur activité.

3. INSCRIPTION
Vous devez avoir au moins 18 ans pour utiliser StyleLink. Lors de l'inscription, vous fournissez des informations exactes et complètes. Vous êtes responsable de la sécurité de votre compte.

4. RÉSERVATIONS
Les réservations sont soumises à disponibilité. Le paiement est requis au moment de la réservation. Les annulations sont gratuites jusqu'à 24 heures avant le rendez-vous.

5. PRESTATAIRES
Les prestataires sont des professionnels indépendants. StyleLink n'emploie pas les prestataires et ne garantit pas la qualité de leurs services.

6. AVIS ET ÉVALUATIONS
Les avis doivent être honnêtes et respectueux. StyleLink se réserve le droit de supprimer les avis inappropriés.

7. LIMITATION DE RESPONSABILITÉ
StyleLink n'est pas responsable des litiges entre clients et prestataires. Notre responsabilité est limitée au montant des frais de service payés.

8. MODIFICATIONS
StyleLink se réserve le droit de modifier ces conditions à tout moment. Les modifications prennent effet dès leur publication.

9. CONTACT
Pour toute question : support@stylelink.app
''';
    }
    return '''
TERMS OF SERVICE — STYLELINK

Last updated: August 31, 2026

1. ACCEPTANCE OF TERMS
By using StyleLink ("the App"), you agree to these Terms of Service. If you do not agree, please do not use the App.

2. DESCRIPTION OF SERVICE
StyleLink is a platform connecting clients with beauty and haircare service providers in Cameroon. The App allows clients to search, book, and pay for services, and allows providers to manage their business.

3. REGISTRATION
You must be at least 18 years old to use StyleLink. You provide accurate and complete information during registration. You are responsible for your account security.

4. BOOKINGS
Bookings are subject to availability. Payment is required at the time of booking. Cancellations are free up to 24 hours before the appointment.

5. PROVIDERS
Providers are independent professionals. StyleLink does not employ providers and does not guarantee the quality of their services.

6. REVIEWS AND RATINGS
Reviews must be honest and respectful. StyleLink reserves the right to remove inappropriate reviews.

7. LIMITATION OF LIABILITY
StyleLink is not responsible for disputes between clients and providers. Our liability is limited to the amount of service fees paid.

8. MODIFICATIONS
StyleLink reserves the right to modify these terms at any time. Modifications take effect upon publication.

9. CONTACT
For questions: support@stylelink.app
''';
  }

  // ── Privacy Policy ───────────────────────────────────────

  String _privacyPolicy(LanguageProvider lang) {
    if (lang.isFrench) {
      return '''
POLITIQUE DE CONFIDENTIALITÉ — STYLELINK

Dernière mise à jour : 31 août 2026

1. COLLECTE DES DONNÉES
Nous collectons les informations que vous fournissez lors de l'inscription (nom, e-mail, téléphone), vos données de réservation, vos avis, et les données d'utilisation de l'Application.

2. UTILISATION DES DONNÉES
Vos données sont utilisées pour :
- Fournir et améliorer nos services
- Faciliter les réservations entre clients et prestataires
- Vous envoyer des notifications de réservation
- Assurer la sécurité de la plateforme

3. PARTAGE DES DONNÉES
Nous ne vendons pas vos données. Vos données sont partagées uniquement avec :
- Le prestataire concerné pour une réservation
- Les services d'hébergement (Supabase) pour le stockage sécurisé

4. SÉCURITÉ
Nous utilisons le chiffrement de bout en bout et des politiques de sécurité au niveau des lignes (RLS) via Supabase.

5. CONSERVATION
Vos données sont conservées tant que votre compte est actif. Vous pouvez demander la suppression de votre compte à tout moment.

6. VOS DROITS
Vous avez le droit d'accéder, modifier ou supprimer vos données. Contactez-nous à support@stylelink.app.

7. COOKIES
L'Application utilise des cookies techniques nécessaires à son fonctionnement.

8. CONTACT
Pour toute question sur la confidentialité : support@stylelink.app
''';
    }
    return '''
PRIVACY POLICY — STYLELINK

Last updated: August 31, 2026

1. DATA COLLECTION
We collect information you provide during registration (name, email, phone), your booking data, reviews, and App usage data.

2. DATA USAGE
Your data is used to:
- Provide and improve our services
- Facilitate bookings between clients and providers
- Send you booking notifications
- Ensure platform security

3. DATA SHARING
We do not sell your data. Your data is shared only with:
- The relevant provider for a booking
- Hosting services (Supabase) for secure storage

4. SECURITY
We use end-to-end encryption and row-level security (RLS) policies via Supabase.

5. RETENTION
Your data is retained while your account is active. You can request account deletion at any time.

6. YOUR RIGHTS
You have the right to access, modify, or delete your data. Contact us at support@stylelink.app.

7. COOKIES
The App uses technical cookies necessary for its operation.

8. CONTACT
For privacy questions: support@stylelink.app
''';
  }
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
          color: _expanded
              ? const Color(0x22F4665C)
              : theme.divider,
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
