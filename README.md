# 🐝 BeeFootFlow - Infrastructure & Database

Ce dépôt centralise la configuration Kubernetes (Helm/ArgoCD) et le schéma de données pour l'application de suivi de baby-foot **BeeFootFlow**.

---

## 🏗️ Architecture du Projet

L'écosystème repose sur trois piliers :
1.  **Frontend & Backend** : Déployés sur Kubernetes via Helm.
2.  **GitOps** : Automatisation via ArgoCD et Image Updater.
3.  **Persistence** : Base de données PostgreSQL optimisée avec calcul automatique des statistiques.

---

## 📊 Base de Données (PostgreSQL)

Le schéma est conçu pour supporter des matchs en **1v1** et **2v2** avec un suivi précis des performances physiques (vitesse de balle, temps de réaction).

### 📂 Structure des Tables

| Table | Description |
| :--- | :--- |
| `users` | Profils joueurs : Elo, MMR, Peak Elo, et statistiques globales. |
| `matches` | Historique des sessions : scores, durée, vitesse moyenne et statut. |
| `match_players` | Table de liaison : définit qui joue dans quelle équipe (A ou B). |
| `goals` | Détail de chaque but : vitesse de la balle et temps écoulé. |

### ⚡ Système Elo & Automatisation
Le projet utilise un **Trigger PL/pgSQL** (`update_user_stats`) qui s'active dès qu'un match passe au statut `finished`. 

**Ce qu'il fait automatiquement :**
* **Calcul Elo** : Gain de **+10** pour les vainqueurs, perte de **-10** pour les perdants (avec sécurité à 0).
* **Peak Elo** : Met à jour le record historique du joueur si le nouvel Elo est supérieur.
* **Stats Globales** : Incrémente le total des matchs, des victoires et des buts marqués.
* **MMR** : Aligné sur l'Elo pour le matchmaking futur.

### 📈 Vues Analytics
Deux vues SQL sont disponibles pour simplifier l'affichage côté Frontend :
* `leaderboard` : Classement des joueurs par Elo avec calcul du **Win Rate** en temps réel.
* `match_summary` : Résumé technique des matchs (vitesse de balle moyenne, stats de buts).

---

## 📂 Structure des Templates Kubernetes

| Fichier | Rôle |
| :--- | :--- |
| `deployment-backend.yaml` | API Node/Go gérant la logique métier et la DB. |
| `deployment-frontend.yaml` | Interface utilisateur React/Vue/Next. |
| `service-*.yaml` | Exposition des services (NodePorts 30090/30091). |
| `configmap-*.yaml` | Configuration environnementale (URL DB, OAuth). |
| `job-tls-secret.yaml` | Gestion des certificats HTTPS. |

---

## 🚀 Déploiement CI/CD

Le déploiement est piloté par **ArgoCD** avec une stratégie **GitOps**.

```yaml
# Stratégie Image Updater (extrait)
argocd-image-updater.argoproj.io/back.update-strategy: latest
argocd-image-updater.argoproj.io/write-back-method: argocd
