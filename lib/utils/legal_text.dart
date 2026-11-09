/// In-app legal copy shown from Help & Support.
///
/// Keep this in sync with `privacy.html` and `terms.html` at the project root.
/// These texts describe the app's actual data flows: Supabase for auth,
/// database and storage; Firebase for push notifications/analytics; optional
/// Sentry crash reporting; optional Resend email for provider nudges. They
/// deliberately do not claim end-to-end encryption.
class LegalText {
  const LegalText._();

  static String terms({required bool french}) {
    if (french) {
      return '''
CONDITIONS D'UTILISATION — STYLELINK

Dernière mise à jour : 9 novembre 2026

1. ACCEPTATION
En utilisant StyleLink, vous acceptez ces conditions. Si vous ne les acceptez pas, n'utilisez pas l'Application.

2. SERVICE
StyleLink met en relation des clients et des prestataires indépendants de beauté et de coiffure au Cameroun. StyleLink facilite la découverte, la réservation et la messagerie ; StyleLink n'est pas partie au contrat de service entre le client et le prestataire.

3. COMPTE
Vous devez avoir au moins 18 ans, fournir des informations exactes et garder vos identifiants confidentiels. Un compte par personne. Vous pouvez supprimer votre compte depuis l'Application.

4. RÉSERVATIONS ET PAIEMENT
Une demande de réservation reste en attente jusqu'à l'acceptation du prestataire. Les prix sont affichés en FCFA. Sauf indication contraire, le paiement se fait directement au prestataire en espèces ou par mobile money ; StyleLink ne traite pas les paiements. Les conditions d'annulation et de report sont fixées par le prestataire. StyleLink peut annuler une réservation en cas de fraude, d'abus ou d'erreur manifeste.

5. PRESTATAIRES
Les prestataires sont des professionnels indépendants. Ils sont responsables de leurs licences, assurances, impôts, prix, disponibilités et de la qualité de leurs services. StyleLink peut retirer un profil qui enfreint ces conditions.

6. AVIS
Les avis sont possibles après un service terminé. Ils doivent être honnêtes et respectueux. StyleLink peut retirer un contenu illégal, trompeur ou abusif.

7. UTILISATION ACCEPTABLE
Vous ne devez pas harceler, menacer, usurper l'identité d'autrui, publier du contenu illégal, tenter de contourner la sécurité, ni utiliser l'Application pour spam ou fraude.

8. RESPONSABILITÉ
L'Application est fournie « en l'état ». Dans la mesure permise par la loi, StyleLink n'est pas responsable des actes des prestataires ou des clients, ni des dommages indirects. Rien dans ces conditions n'exclut une responsabilité qui ne peut légalement être exclue.

9. SUPPRESSION DU COMPTE
La suppression du compte est disponible dans l'Application. Elle supprime le compte et les données associées, sous réserve des obligations légales de conservation.

10. MODIFICATIONS
Nous pouvons modifier ces conditions. La version en vigueur est publiée dans l'Application et sur le site.

11. DROIT APPLICABLE
Ces conditions sont régies par le droit camerounais, sans préjudice des protections impératives applicables aux consommateurs.

12. CONTACT
support@stylelink.app
''';
    }

    return '''
TERMS OF SERVICE — STYLELINK

Last updated: 9 November 2026

1. ACCEPTANCE
By using StyleLink you agree to these Terms. If you do not agree, do not use the App.

2. SERVICE
StyleLink connects clients with independent beauty and barbering providers in Cameroon. StyleLink facilitates discovery, booking, and messaging; it is not a party to the service agreement between a client and a provider.

3. ACCOUNT
You must be at least 18, provide accurate information, and keep your credentials secure. One account per person. You can delete your account from the App.

4. BOOKINGS AND PAYMENT
A booking request stays pending until the provider accepts it. Prices are shown in FCFA. Unless stated otherwise, payment is made directly to the provider in cash or by mobile money; StyleLink does not process payments. Cancellation and rescheduling terms are set by the provider. StyleLink may cancel a booking for fraud, abuse, or clear error.

5. PROVIDERS
Providers are independent professionals. They are responsible for their licences, insurance, taxes, pricing, availability, and the quality of their services. StyleLink may remove a profile that violates these Terms.

6. REVIEWS
Reviews are available after a completed service. They must be honest and respectful. StyleLink may remove illegal, misleading, or abusive content.

7. ACCEPTABLE USE
Do not harass, threaten, impersonate others, post illegal content, attempt to bypass security, or use the App for spam or fraud.

8. LIABILITY
The App is provided "as is". To the extent permitted by law, StyleLink is not responsible for the acts of providers or clients, or for indirect damages. Nothing in these Terms excludes liability that cannot legally be excluded.

9. ACCOUNT DELETION
Account deletion is available in the App. It removes the account and associated data, subject to legal retention obligations.

10. CHANGES
We may update these Terms. The current version is published in the App and on the website.

11. GOVERNING LAW
These Terms are governed by the laws of Cameroon, without prejudice to mandatory consumer protections.

12. CONTACT
support@stylelink.app
''';
  }

  static String privacy({required bool french}) {
    if (french) {
      return '''
POLITIQUE DE CONFIDENTIALITÉ — STYLELINK

Dernière mise à jour : 9 novembre 2026

1. RESPONSABLE DU TRAITEMENT
StyleLink est responsable du traitement des données décrites ici. Contact : support@stylelink.app.

2. DONNÉES COLLECTÉES
- Compte : nom, e-mail, téléphone, rôle (client/prestataire), ville, photo de profil, langue.
- Activité : réservations, services choisis, horaires, statuts, prix, avis, favoris et messages.
- Prestataires : nom commercial, catégorie, ville/quartier, biographie, photos, horaires, services et tarifs.
- Localisation : position précise uniquement si vous accordez la permission, afin d'enregistrer l'arrivée du prestataire. Vous pouvez refuser ; la réservation continue sans GPS.
- Notifications : jeton d'appareil Firebase (FCM) et préférences.
- Diagnostics : données techniques, journaux d'erreurs et statistiques d'usage (Firebase Analytics ; Sentry si configuré).

3. UTILISATION
Fournir le service, gérer les réservations et la messagerie, envoyer les notifications demandées, assurer la sécurité et prévenir la fraude, améliorer l'Application, respecter nos obligations légales.

4. PARTAGE
Nous ne vendons pas vos données. Elles peuvent être partagées avec :
- le prestataire concerné par une réservation (et le client, côté prestataire) ;
- Supabase (authentification, base de données, stockage) ;
- Google Firebase (notifications push et analytics) ;
- Sentry, si la remontée de crashes est activée ;
- Resend, pour les e-mails de rappel aux prestataires ;
- les autorités, lorsque la loi l'exige.
Ces prestataires peuvent traiter des données hors du Cameroun avec des garanties contractuelles appropriées.

5. SÉCURITÉ
Les échanges utilisent HTTPS/TLS. L'accès aux données est limité par des politiques de sécurité au niveau des lignes (RLS) et par des rôles à privilèges minimaux. Les codes de vérification sont stockés séparément et ne sont pas accessibles aux prestataires. Aucun système n'est parfaitement sûr ; n'envoyez pas de données sensibles dans les messages.

6. CONSERVATION
Les données sont conservées pendant que votre compte est actif. La suppression du compte supprime le profil, les réservations, messages, avis, favoris et photos associés, sous réserve des obligations légales et des sauvegardes techniques temporaires.

7. VOS DROITS
Selon la loi applicable, vous pouvez demander l'accès, la correction ou la suppression de vos données, vous opposer à certains traitements, ou introduire une réclamation auprès de l'autorité compétente. Contact : support@stylelink.app.

8. LOCALISATION ET NOTIFICATIONS
La localisation et les notifications sont facultatives. Refuser la localisation n'empêche pas de réserver. Vous pouvez désactiver les notifications dans l'Application ou les réglages du téléphone.

9. ENFANTS
L'Application est destinée aux personnes de 18 ans et plus. Nous ne collectons pas sciemment de données d'enfants.

10. COOKIES ET STOCKAGE LOCAL
Le site utilise le stockage technique nécessaire au fonctionnement de l'Application (session, préférences, cache hors ligne). Nous n'utilisons pas de cookies publicitaires.

11. MODIFICATIONS
Nous pouvons mettre à jour cette politique. La version en vigueur est publiée dans l'Application et sur le site.

12. CONTACT
support@stylelink.app
''';
    }

    return '''
PRIVACY POLICY — STYLELINK

Last updated: 9 November 2026

1. CONTROLLER
StyleLink is responsible for the processing described here. Contact: support@stylelink.app.

2. DATA WE COLLECT
- Account: name, email, phone, role (client/provider), city, profile photo, language.
- Activity: bookings, selected services, times, statuses, prices, reviews, favourites, and messages.
- Provider details: business name, category, city/quarter, bio, photos, working hours, services, and prices.
- Location: precise location only when you grant permission, used to record a provider's arrival. You can refuse; the booking continues without GPS.
- Notifications: Firebase device token (FCM) and preferences.
- Diagnostics: technical data, error logs, and usage analytics (Firebase Analytics; Sentry when configured).

3. HOW WE USE IT
To provide the service, manage bookings and messaging, send requested notifications, keep the platform secure and prevent fraud, improve the App, and meet legal obligations.

4. SHARING
We do not sell your data. We share it with:
- the provider for a booking (and the client, on the provider side);
- Supabase (authentication, database, storage);
- Google Firebase (push notifications and analytics);
- Sentry, when crash reporting is enabled;
- Resend, for provider reminder emails;
- authorities when required by law.
These providers may process data outside Cameroon under appropriate contractual safeguards.

5. SECURITY
Traffic uses HTTPS/TLS. Access is restricted by row-level security (RLS) policies and least-privilege roles. Verification codes are stored separately from booking rows and are not readable by providers. No system is perfectly secure; do not send sensitive information in messages.

6. RETENTION
Data is retained while your account is active. Deleting your account deletes the associated profile, bookings, messages, reviews, favourites, and photos, subject to legal retention obligations and temporary technical backups.

7. YOUR RIGHTS
Depending on applicable law, you may request access, correction or deletion of your data, object to certain processing, or complain to the competent authority. Contact: support@stylelink.app.

8. LOCATION AND NOTIFICATIONS
Location and notifications are optional. Refusing location does not prevent booking. You can disable notifications in the App or your device settings.

9. CHILDREN
The App is intended for people aged 18 and over. We do not knowingly collect children's data.

10. COOKIES AND LOCAL STORAGE
The website uses technical storage required to run the App (session, preferences, offline cache). We do not use advertising cookies.

11. CHANGES
We may update this policy. The current version is published in the App and on the website.

12. CONTACT
support@stylelink.app
''';
  }
}
