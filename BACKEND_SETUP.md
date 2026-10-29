# Destination Gabon — démarrage du backend

Le site public est hébergé sur GitHub Pages. GitHub Pages ne fournit ni authentification, ni base de données, ni API. Le backend est donc préparé pour Supabase (PostgreSQL + Auth + Row Level Security).

## 1. Créer le projet
1. Créer un projet sur https://supabase.com/
2. Ouvrir **SQL Editor** puis exécuter intégralement le fichier `supabase/schema.sql`.
3. Dans **Authentication > URL Configuration**, ajouter :
   - Site URL : `https://zavierlevisionnaire.github.io/destination-gabon/`
   - Redirect URL : `https://zavierlevisionnaire.github.io/destination-gabon/**`

## 2. Créer l'administrateur national
1. Dans **Authentication > Users**, créer le compte avec une adresse e-mail que tu contrôles.
2. Copier son UUID.
3. Dans SQL Editor, exécuter :
   ```sql
   update public.profiles
   set role = 'national_admin'
   where id = 'COLLER-ICI-UUID-DU-COMPTE';
   ```
4. Ne jamais communiquer ni intégrer une clé `service_role` dans le site.

## 3. Configuration publique
Le navigateur utilisera uniquement l'URL du projet et la clé **anon/public**. Ces deux valeurs se récupèrent dans **Project Settings > API**. Elles seront placées dans un fichier de configuration public ; la sécurité dépend des politiques RLS du schéma.

## 4. Rôles prévus
- `national_admin` : gestion nationale et validation finale.
- `provincial_guide` : gestion et contrôle des données de sa province.
- `departmental_guide` : gestion et contrôle des données de son département.
- `provider` : gestion de ses propres fiches.

## 5. Tables créées
`provinces`, `departments`, `localities`, `profiles`, `providers`, `tourism_content`, `inquiries`, `reservations`.

## État
Le schéma et les politiques d'accès constituent la première fondation du backend. Le site actuel reste en mode démonstration tant que le projet Supabase n'est pas créé, configuré et relié aux pages. Aucun vrai compte ni donnée de production n'est activé à ce stade.
