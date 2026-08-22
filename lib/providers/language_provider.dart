import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported app languages.
enum AppLanguage { english, french }

/// Manages the current language selection with SharedPreferences persistence.
///
/// Usage:
/// ```dart
/// // Read a translated string
/// final t = Localizations.of(context).t;
/// Text(t('sign_out'))
///
/// // Change language
/// context.read<LanguageProvider>().setLanguage(AppLanguage.french);
/// ```
class LanguageProvider extends ChangeNotifier {
  static const _key = 'app_language';

  AppLanguage _language = AppLanguage.english;

  AppLanguage get language => _language;

  Locale get locale =>
      _language == AppLanguage.french ? const Locale('fr') : const Locale('en');

  bool get isFrench => _language == AppLanguage.french;

  /// Load saved preference at app startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == 'fr') {
      _language = AppLanguage.french;
    } else {
      _language = AppLanguage.english;
    }
    notifyListeners();
  }

  /// Switch to English.
  void setEnglish() => _setLanguage(AppLanguage.english);

  /// Switch to French.
  void setFrench() => _setLanguage(AppLanguage.french);

  /// Toggle between English and French.
  void toggle() {
    if (_language == AppLanguage.english) {
      setFrench();
    } else {
      setEnglish();
    }
  }

  void _setLanguage(AppLanguage lang) {
    if (_language == lang) return;
    _language = lang;
    _save();
    notifyListeners();
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _language == AppLanguage.french ? 'fr' : 'en');
  }

  /// Convenience method — returns the translated string for [key].
  /// Falls back to English if French is missing.
  String translate(String key) {
    final map = _language == AppLanguage.french ? _fr : _en;
    return map[key] ?? _en[key] ?? key;
  }
}

// =============================================================================
// Translation maps
// =============================================================================

const Map<String, String> _en = {
  // ── Navigation ──
  'home': 'Home',
  'search': 'Search',
  'bookings': 'Bookings',
  'messages': 'Messages',
  'profile': 'Profile',
  'schedule': 'Schedule',
  'services': 'Services',
  'earnings': 'Earnings',
  'good_morning': 'Good Morning',
  'top_rated': 'Top Rated Professionals',
  'search_hint_long': 'Search stylists, services, salons...',
  'dashboard': 'Dashboard',
  'provider_mode': 'Provider Mode',
  'client_mode': 'Client Mode',

  // ── Auth ──
  'sign_in': 'Sign In',
  'sign_up': 'Sign Up',
  'sign_out': 'Sign Out',
  'sign_out_confirm_title': 'Sign Out?',
  'sign_out_confirm_body': 'You will be returned to the sign-in screen.',
  'delete_account': 'Delete Account',
  'delete_account_confirm_title': 'Delete Account?',
  'delete_account_confirm_body': 'This action is permanent and cannot be undone. All your data will be deleted.',
  'cancel': 'Cancel',
  'email': 'Email',
  'password': 'Password',
  'full_name': 'Full Name',
  'or_continue_with': 'Or continue with',
  'google': 'Google',
  'no_account': "Don't have an account?",
  'has_account': 'Already have an account?',
  'create_account': 'Create Account',
  'welcome_back': 'Welcome back',
  'welcome_to_stylelink': 'Welcome to StyleLink',

  // ── Client Profile ──
  'my_favorites': 'My Favorites',
  'no_favorites': 'No favorites saved yet',
  'no_favorites_sub': 'Aucun favori enregistré',
  'stylists_you_saved': 'Stylists you saved with the heart icon.',
  'settings': 'Settings',
  'appearance': 'Appearance',
  'language': 'Language',
  'light': 'Light',
  'dark': 'Dark',
  'system': 'System',
  'bookings_count': 'Bookings',
  'saved_count': 'Saved',

  // ── Become a Provider ──
  'become_provider': 'Become a Provider',
  'become_provider_sub': 'Offer your services and earn money.',
  'become_provider_sub_fr': 'Proposez vos services et gagnez de l\'argent.',
  'set_up_business': 'Set Up Your Business',
  'configurez_activite': 'Configurez votre activité',
  'business_name': 'Business Name',
  'business_name_hint': 'Business Name / Nom du salon',
  'category': 'Category',
  'category_hint': 'Category / Catégorie',
  'city': 'City',
  'city_hint': 'City / Ville',
  'start_offering': 'Start Offering Services / Commencer',
  'you_are_now_provider': 'You are now a provider! Use the toggle in the top bar to switch to Provider Mode.',

  // ── Provider Profile ──
  'verified_stylist': 'Verified Stylist',
  'rating': 'Rating',
  'completed': 'Completed',
  'location': 'Location',
  'quick_actions': 'Quick Actions',
  'actions_rapides': 'Actions rapides',
  'manage_portfolio': 'Manage Portfolio',
  'manage_portfolio_sub': 'Gérer le Portfolio',
  'working_hours': 'Working Hours & Availability',
  'working_hours_sub': 'Horaires de travail',
  'service_catalog': 'Service Catalog & Pricing',
  'service_catalog_sub': 'Catalogue de services',
  'portfolio': 'Portfolio',
  'portfolio_sub': 'Réalisations',
  'no_business': 'No business listed yet',
  'no_business_sub': 'Create your listing to start receiving bookings.\nCréez votre fiche pour recevoir des réservations.',
  'list_my_business': 'List My Business',
  'manage_portfolio_empty': 'No work samples uploaded yet',
  'manage_portfolio_empty_sub': 'Add up to 7 photos of your best work.',
  'add_work_photo': 'Add Work Photo',
  'uploading': 'Uploading…',
  'max_capacity': 'Maximum capacity reached.',
  'spots_left': 'spots left',
  'showcase_best_work': 'Showcase your best work.',
  'remove_photo': 'Remove photo?',
  'remove_photo_sub': 'This will permanently delete the photo from your portfolio.',

  // ── Home / Service Feed ──
  'find_your_stylist': 'Find Your Stylist',
  'explore_services': 'Explore Services',
  'popular_near_you': 'Popular near you',
  'book_now': 'Book Now',
  'provider_busy': 'Provider Currently Busy',
  'provider_busy_sub': 'Prestataire en session',
  'available': 'Available',
  'busy': 'Busy',
  'favorites': 'Favorites',

  // ── Bookings ──
  'upcoming': 'Upcoming',
  'past': 'Past',
  'no_bookings': 'No bookings yet',
  'confirmed': 'Confirmed',
  'arrived': 'Arrived',
  'in_progress': 'In Progress',
  'completed_status': 'Completed',
  'cancelled': 'Cancelled',
  'pending': 'Pending',
  'mark_arrived': 'Mark as Arrived',
  'start_work': 'Start Work',
  'complete_service': 'Complete Service',
  'terminer': 'Terminer',
  'complete_service_confirm': 'Complete Service?',
  'session_duration': 'Session Duration',
  'service_completed': 'Service completed successfully!',
  'location_unavailable': 'Location unavailable; proceeding without GPS',

  // ── Booking Tracker (Provider) ──
  'open_gps': 'Open GPS Navigation',
  'enter_pin': 'Enter Verification PIN',
  'pin_hint': 'Enter the 4-digit PIN shown to the client',
  'verify': 'Verify',
  'pin_required': 'PIN is required',
  'pin_exact': 'PIN must be exactly 4 digits',
  'pin_invalid': 'Invalid PIN. Please check and try again.',

  // ── Active Booking Tracker (Client) ──
  'provider_en_route': 'Provider is En Route',
  'provider_arrived': 'Provider Has Arrived!',
  'prepare_for_service': 'Prepare for service',
  'share_code': 'Share this code with your provider upon arrival to start the session.',
  'service_underway': 'Service Underway',
  'tap_to_rate': 'Tap to rate your experience',
  'call': 'Call',
  'message': 'Message',

  // ── Reviews ──
  'reviews': 'Reviews',
  'no_reviews': 'No reviews yet',
  'submit_review': 'Submit Review',
  'soumettre': 'Soumettre',
  'leave_comment': 'Leave a comment for your stylist…',
  'thank_you_review': 'Thank you for your review!',
  'review_submitted': 'Review submitted successfully',

  // ── Search ──
  'search_hint': 'Search stylists, services…',
  'searching': 'Searching…',
  'no_results': 'No stylists found',
  'try_different': 'Try a different search term',
  'all': 'All',
  'barbing': 'Barbing',
  'braiding': 'Braiding',
  'coloring': 'Coloring',
  'locs': 'Locs',
  'nails': 'Nails',
  'makeup': 'Makeup',
  'skincare': 'Skincare',

  // ── Messages ──
  'no_messages': 'No conversations yet',
  'start_chat': 'Send a message to start chatting',
  'type_message': 'Type a message…',

  // ── General ──
  'loading': 'Loading…',
  'error': 'Error',
  'retry': 'Retry',
  'save': 'Save',
  'delete': 'Delete',
  'edit': 'Edit',
  'close': 'Close',
  'submit': 'Submit',
  'required': 'Required',
  'no_profile': 'No profile found',
  'no_profile_sub':
      'We could not read your profile.\nRun supabase/schema.sql in the Supabase SQL editor, then sign out and back in.',
  'could_not_load': 'Could not load favorites',
  'pull_to_refresh': 'Pull to refresh or try again later.',
  'profile_photo_updated': 'Profile photo updated!',
  'upload_failed': 'Upload failed:',
  'could_not_remove': 'Could not remove photo:',
  'error_location': 'Error getting location',
  'pin_verified': 'PIN verified! Starting session…',
  'session_started': 'Session started',
  'photo_added': 'Photo added!',
};

const Map<String, String> _fr = {
  // ── Navigation ──
  'home': 'Accueil',
  'search': 'Rechercher',
  'bookings': 'Réservations',
  'messages': 'Messages',
  'profile': 'Profil',
  'schedule': 'Agenda',
  'services': 'Services',
  'earnings': 'Revenus',
  'good_morning': 'Bonjour',
  'top_rated': 'Stylistes Populaires',
  'search_hint_long': 'Rechercher coiffeurs, services, salons...',
  'dashboard': 'Tableau de bord',
  'provider_mode': 'Mode Prestataire',
  'client_mode': 'Mode Client',

  // ── Auth ──
  'sign_in': 'Se connecter',
  'sign_up': "S'inscrire",
  'sign_out': 'Se déconnecter',
  'delete_account': 'Supprimer le compte',
  'delete_account_confirm_title': 'Supprimer le compte ?',
  'delete_account_confirm_body': 'Cette action est irréversible. Toutes vos données seront supprimées.',
  'sign_out_confirm_title': 'Se déconnecter ?',
  'sign_out_confirm_body': 'Vous retournerez à l\'écran de connexion.',
  'cancel': 'Annuler',
  'email': 'E-mail',
  'password': 'Mot de passe',
  'full_name': 'Nom complet',
  'or_continue_with': 'Ou continuer avec',
  'google': 'Google',
  'no_account': "Vous n'avez pas de compte ?",
  'has_account': 'Vous avez déjà un compte ?',
  'create_account': 'Créer un compte',
  'welcome_back': 'Bon retour',
  'welcome_to_stylelink': 'Bienvenue sur StyleLink',

  // ── Client Profile ──
  'my_favorites': 'Mes Favoris',
  'no_favorites': 'Aucun favori enregistré',
  'no_favorites_sub': '',
  'stylists_you_saved': 'Coiffeurs sauvegardés avec l\'icône cœur.',
  'settings': 'Paramètres',
  'appearance': 'Apparence',
  'language': 'Langue',
  'light': 'Clair',
  'dark': 'Sombre',
  'system': 'Système',
  'bookings_count': 'Réservations',
  'saved_count': 'Sauvegardés',

  // ── Become a Provider ──
  'become_provider': 'Devenir Prestataire',
  'become_provider_sub': 'Proposez vos services et gagnez de l\'argent.',
  'become_provider_sub_fr': 'Proposez vos services et gagnez de l\'argent.',
  'set_up_business': 'Configurez Votre Activité',
  'configurez_activite': 'Configurez votre activité',
  'business_name': 'Nom du salon',
  'business_name_hint': 'Nom du salon',
  'category': 'Catégorie',
  'category_hint': 'Catégorie',
  'city': 'Ville',
  'city_hint': 'Ville',
  'start_offering': 'Commencer à Proposer',
  'you_are_now_provider': 'Vous êtes maintenant prestataire ! Utilisez le bouton dans la barre du haut pour basculer.',

  // ── Provider Profile ──
  'verified_stylist': 'Esthéticien Vérifié',
  'rating': 'Note',
  'completed': 'Terminées',
  'location': 'Localisation',
  'quick_actions': 'Actions Rapides',
  'actions_rapides': 'Actions rapides',
  'manage_portfolio': 'Gérer le Portfolio',
  'manage_portfolio_sub': 'Gérer le Portfolio',
  'working_hours': 'Horaires & Disponibilité',
  'working_hours_sub': 'Horaires de travail',
  'service_catalog': 'Catalogue & Tarifs',
  'service_catalog_sub': 'Catalogue de services',
  'portfolio': 'Réalisations',
  'portfolio_sub': 'Réalisations',
  'no_business': 'Aucune activité enregistrée',
  'no_business_sub': 'Créez votre fiche pour recevoir des réservations.',
  'list_my_business': 'Inscrire Mon Activité',
  'manage_portfolio_empty': 'Aucun exemple de travail',
  'manage_portfolio_empty_sub': 'Ajoutez jusqu\'à 7 photos de votre meilleur travail.',
  'add_work_photo': 'Ajouter une Photo',
  'uploading': 'Téléversement…',
  'max_capacity': 'Capacité maximale atteinte.',
  'spots_left': 'places restantes',
  'showcase_best_work': 'Présentez votre meilleur travail.',
  'remove_photo': 'Supprimer la photo ?',
  'remove_photo_sub': 'Cette photo sera définitivement supprimée de votre portfolio.',

  // ── Home / Service Feed ──
  'find_your_stylist': 'Trouvez Votre Coiffeur',
  'explore_services': 'Explorer les Services',
  'popular_near_you': 'Populaires près de chez vous',
  'book_now': 'Réserver',
  'provider_busy': 'Prestataire en Session',
  'provider_busy_sub': 'Prestataire en session',
  'available': 'Disponible',
  'busy': 'Occupé',
  'favorites': 'Favoris',

  // ── Bookings ──
  'upcoming': 'À venir',
  'past': 'Passées',
  'no_bookings': 'Aucune réservation',
  'confirmed': 'Confirmée',
  'arrived': 'Arrivé',
  'in_progress': 'En cours',
  'completed_status': 'Terminée',
  'cancelled': 'Annulée',
  'pending': 'En attente',
  'mark_arrived': 'Marquer Arrivé',
  'start_work': 'Commencer le Travail',
  'complete_service': 'Terminer le Service',
  'terminer': 'Terminer',
  'complete_service_confirm': 'Terminer le service ?',
  'session_duration': 'Durée de la Session',
  'service_completed': 'Service terminé avec succès !',
  'location_unavailable': 'Position indisponible ; poursuite sans GPS',

  // ── Booking Tracker (Provider) ──
  'open_gps': 'Ouvrir la Navigation GPS',
  'enter_pin': 'Entrer le Code PIN',
  'pin_hint': 'Entrez le code à 4 chiffres affiché au client',
  'verify': 'Vérifier',
  'pin_required': 'Le PIN est requis',
  'pin_exact': 'Le PIN doit contenir 4 chiffres',
  'pin_invalid': 'PIN incorrect. Veuillez réessayer.',

  // ── Active Booking Tracker (Client) ──
  'provider_en_route': 'Le Prestataire Est en Route',
  'provider_arrived': 'Le Prestataire Est Arrivé !',
  'prepare_for_service': 'Préparez-vous pour le service',
  'share_code': 'Partagez ce code avec votre prestataire à son arrivée pour démarrer la session.',
  'service_underway': 'Service en Cours',
  'tap_to_rate': 'Appuyez pour évaluer votre expérience',
  'call': 'Appeler',
  'message': 'Message',

  // ── Reviews ──
  'reviews': 'Avis',
  'no_reviews': 'Aucun avis pour le moment',
  'submit_review': 'Soumettre un Avis',
  'soumettre': 'Soumettre',
  'leave_comment': 'Laissez un commentaire pour votre coiffeur…',
  'thank_you_review': 'Merci pour votre avis !',
  'review_submitted': 'Avis soumis avec succès',

  // ── Search ──
  'search_hint': 'Rechercher coiffeurs, services…',
  'searching': 'Recherche…',
  'no_results': 'Aucun coiffeur trouvé',
  'try_different': 'Essayez un autre terme de recherche',
  'all': 'Tous',
  'barbing': 'Barbier',
  'braiding': 'Tresses',
  'coloring': 'Coloration',
  'locs': 'Dreadlocks',
  'nails': 'Manucure',
  'makeup': 'Maquillage',
  'skincare': 'Soins',

  // ── Messages ──
  'no_messages': 'Aucune conversation',
  'start_chat': 'Envoyez un message pour commencer',
  'type_message': 'Tapez un message…',

  // ── General ──
  'loading': 'Chargement…',
  'error': 'Erreur',
  'retry': 'Réessayer',
  'save': 'Enregistrer',
  'delete': 'Supprimer',
  'edit': 'Modifier',
  'close': 'Fermer',
  'submit': 'Soumettre',
  'required': 'Obligatoire',
  'no_profile': 'Profil introuvable',
  'no_profile_sub':
      'Nous n\'avons pas pu lire votre profil.\nExécutez supabase/schema.sql dans l\'éditeur SQL Supabase, puis déconnectez-vous et reconnectez-vous.',
  'could_not_load': 'Impossible de charger les favoris',
  'pull_to_refresh': 'Tirez pour rafraîchir ou réessayez plus tard.',
  'profile_photo_updated': 'Photo de profil mise à jour !',
  'upload_failed': 'Échec du téléversement :',
  'could_not_remove': 'Impossible de supprimer la photo :',
  'error_location': 'Erreur de géolocalisation',
  'pin_verified': 'PIN vérifié ! Début de la session…',
  'session_started': 'Session commencée',
  'photo_added': 'Photo ajoutée !',
};

/// InheritedWidget that provides [LanguageProvider] to the widget tree.
class LanguageScope extends InheritedWidget {
  const LanguageScope({
    super.key,
    required this.provider,
    required super.child,
  });

  final LanguageProvider provider;

  static LanguageProvider of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, 'No LanguageScope found in context');
    return scope!.provider;
  }

  @override
  bool updateShouldNotify(LanguageScope oldWidget) =>
      provider != oldWidget.provider;
}

/// Convenience extension on BuildContext.
extension LanguageScopeExtension on BuildContext {
  LanguageProvider get lang => LanguageScope.of(this);

  /// Shorthand for `lang.translate(key)`.
  String t(String key) => LanguageScope.of(this).translate(key);
}
