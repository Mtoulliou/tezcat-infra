# TEZCAT — Procédure d'ajout d'un utilisateur (admin ou développeur)

> Pour toi, l'administrateur qui enrôle. Tout est fait **en code** :
> aucune modification manuelle dans GitLab ou dans `wg0.conf`.

> ⏱️ ~10 minutes, dont l'essentiel est de l'attente (l'autre personne génère ses clés).

---

## Vue d'ensemble

Ajouter quelqu'un = **modifier deux fichiers** et lancer deux commandes :

| Fichier | Ce qu'on y ajoute | Commande |
|---------|-------------------|----------|
| `terraform-gitlab/users.tf` | le compte GitLab + son niveau d'accès | `terraform apply` |
| `ansible/wireguard.yml` | le pair VPN (clé publique + IP) | `ansible-playbook wireguard.yml` |
| `.sops.yaml` *(admins only)* | sa clé publique age (accès aux secrets) | `sops updatekeys` |

Tout est versionné → `git log` te dit qui a eu accès à quoi et quand.

> ℹ️ La clé age n'est nécessaire que pour les **administrateurs** (ils manipulent
> les secrets chiffrés). Un développeur n'en a pas besoin au départ.

---

## Étape 0 — Attribuer une IP VPN

Consulte le tableau d'attribution (`runbook_wireguard_pair.md`) et choisis une IP
**libre** dans la plage du profil :

| Profil | Plage | Convention |
|--------|-------|------------|
| Admin | `10.0.0.0/24` | à partir de `.10` |
| Dev | `10.0.1.0/24` | à partir de `.10` |
| Shield | `10.0.2.0/24` | à partir de `.10` |

⚠️ Le profil détermine les accès (via les règles nftables du firewall) :
mettre un dev dans la plage admin lui donnerait les droits admin.

---

## Étape 1 — Demander sa clé publique

Envoie-lui le guide correspondant (`GUIDE_DEVELOPPEUR.md` ou
`GUIDE_ADMINISTRATEUR.md`) et demande-lui :

- sa **clé publique WireGuard** (obligatoire)
- sa **clé publique SSH** (administrateurs uniquement, pour l'accès aux VM)
- sa **clé publique age** (administrateurs uniquement, pour déchiffrer les secrets)

> 🔑 Refuse toute clé **privée** qu'on t'enverrait : c'est une erreur de sécurité,
> il faut regénérer la paire.

---

## Étape 2 — Créer le compte GitLab (Terraform)

Édite `terraform-gitlab/users.tf`, section `locals`.

**Pour un développeur** → bloc `devs` :
```hcl
  devs = {
    "prenom.nom" = {
      name  = "Prénom Nom"
      email = "prenom@tezcat.fr"
    }
  }
```

**Pour un administrateur** → bloc `admins` :
```hcl
  admins = {
    # ... existants ...
    "prenom" = {
      name     = "Prénom"
      email    = "prenom@tezcat.fr"
      is_admin = true
    }
  }
```

Applique :
```bash
cd terraform-gitlab/
terraform plan      # vérifier : uniquement des ajouts, aucun "destroy"
terraform apply
```

> Le mot de passe temporaire est celui de `initial_password`
> (chiffré dans `secrets/gitlab.yaml` via SOPS). La personne doit le changer
> à sa 1ʳᵉ connexion.

**Différence de droits :**
- Dev → `developer` sur le groupe : peut cloner et pousser sur des branches,
  passe par Merge Request pour `main`.
- Admin → `owner` sur le groupe + admin de l'instance GitLab.

---

## Étape 3 — Créer le pair VPN (Ansible)

Édite `ansible/wireguard.yml`, section `wg_peers` :
```yaml
    wg_peers:
      # ... pairs existants ...
      - name: "Prénom Nom — Dev"
        public_key: "<sa clé publique WireGuard>"
        allowed_ips: "10.0.1.10/32"      # ← l'IP choisie à l'étape 0
```

⚠️ Toujours en **`/32`** : c'est ce qui épingle la personne à une IP unique et
permet au firewall de l'identifier comme admin ou dev.

Applique :
```bash
cd ansible/
ansible-playbook wireguard.yml --check
ansible-playbook wireguard.yml
```

> ⚠️ Le playbook **redémarre `wg0`** → brève coupure des tunnels actifs.
> Préviens les autres utilisateurs, ou fais-le en dehors des heures de travail.

---

## Étape 4 — (Administrateurs uniquement) Déployer sa clé SSH

Pour qu'un admin accède aux VM, ajoute sa clé publique SSH.

Dans `ansible/harden.yml`, ajoute une tâche (ou complète-la si elle existe) :
```yaml
    - name: Déployer les clés SSH des administrateurs
      ansible.posix.authorized_key:
        user: tezcatadmin
        key: "{{ item }}"
        state: present
      loop:
        - "ssh-ed25519 AAAA... matteo@tezcat"
        - "ssh-ed25519 AAAA... maxime@tezcat"     # ← nouvelle clé
```

Applique :
```bash
ansible-playbook harden.yml
```

> 💡 Mieux : externalise ces clés dans `group_vars/all.yml` sous forme de liste
> `admin_ssh_keys`, pour n'avoir qu'un seul endroit à modifier.

---

## Étape 4bis — (Administrateurs uniquement) Autoriser sa clé age

Pour qu'un admin puisse déchiffrer les secrets (SOPS), ajoute sa clé publique age
dans `.sops.yaml` (à la racine du dépôt infra) :

```yaml
creation_rules:
  - path_regex: (\.enc\.yaml|secrets/.*\.yaml)$
    key_groups:
      - age:
          - age1...matteo
          - age1...maxime          # ← nouvelle clé publique age
          - age1...runner
```

Puis **re-chiffre tous les secrets** pour inclure sa clé :
```bash
find secrets/ -name '*.yaml' -exec sops updatekeys -y {} \;
```

À partir de là, la personne peut déchiffrer les secrets avec sa clé privée age.

> ⚠️ Sans cette étape, l'admin aura accès aux VM (SSH) mais **pas** aux secrets
> chiffrés → ses `terraform apply` échoueront au déchiffrement SOPS.

---

## Étape 5 — Transmettre les informations

Envoie à la personne :

- [ ] Le **guide** correspondant à son profil
- [ ] Son **identifiant GitLab** + le mot de passe temporaire (via un canal sécurisé
      : partage Bitwarden, gestionnaire de secrets, ou en personne — jamais par mail/chat)
- [ ] La **clé publique du serveur WireGuard** :
      `ansible wireguard -m command -a "cat /etc/wireguard/server_public.key" --become`
- [ ] L'**adresse du VPN** + port `51820`
- [ ] Son **IP VPN attribuée**

---

## Étape 6 — Tracer et committer

Mets à jour le **tableau d'attribution des IP** dans `runbook_wireguard_pair.md`,
puis commit :

```bash
git add terraform-gitlab/users.tf ansible/wireguard.yml docs/
git commit -m "feat(access): ajout de Prénom Nom (profil dev)"
git push
```

> C'est ce commit qui rend l'accès **auditable** : dans 6 mois, `git log` te dira
> qui a été ajouté, quand, et avec quel niveau d'accès.

---

## Étape 7 — Vérifier

```bash
# Le pair VPN est actif
ansible wireguard -m command -a "wg show" --become

# Le compte GitLab existe
# → vérifier dans https://10.2.0.2/admin/users
```

Demande à la personne de confirmer qu'elle accède bien à GitLab, et **qu'elle a
changé son mot de passe**.

---

# Retirer un accès (départ, révocation)

Aussi important que l'ajout — et tout aussi rapide.

**1. Révoquer le VPN** — supprimer son bloc de `wg_peers` dans `ansible/wireguard.yml` :
```bash
ansible-playbook wireguard.yml
```
Effet **immédiat** : sans son bloc `[Peer]`, le serveur refuse le handshake.

**2. Désactiver le compte GitLab** — dans `terraform-gitlab/users.tf` :
```hcl
state = "blocked"      # conserve l'historique des contributions
```
(ou supprimer le bloc pour effacer complètement le compte)
```bash
terraform apply
```

**3. Retirer sa clé SSH** de la liste dans Ansible, puis :
```bash
ansible-playbook harden.yml
```

**4. (Admins) Retirer sa clé age** de `.sops.yaml`, puis re-chiffrer :
```bash
find secrets/ -name '*.yaml' -exec sops updatekeys -y {} \;
```
→ il ne peut plus déchiffrer les nouvelles versions des secrets.

**5. Libérer son IP VPN** dans le tableau d'attribution, et **committer** :
```bash
git commit -m "chore(access): révocation de Prénom Nom"
```

> 🔴 Si la personne avait un accès **administrateur**, elle a pu déchiffrer et
> **copier** des secrets par le passé. Retirer sa clé age empêche les accès
> futurs, mais ne rend pas les anciens secrets sûrs → **fais tourner les secrets
> sensibles** qu'elle connaissait (token Proxmox, token GitLab, mots de passe).

---

## Récapitulatif

| Action | Fichier | Commande |
|--------|---------|----------|
| Compte GitLab | `terraform-gitlab/users.tf` | `terraform apply` |
| Accès VPN | `ansible/wireguard.yml` | `ansible-playbook wireguard.yml` |
| Accès SSH (admins) | `ansible/harden.yml` | `ansible-playbook harden.yml` |
| Accès secrets (admins) | `.sops.yaml` | `sops updatekeys` |
| Traçabilité | `runbook_wireguard_pair.md` + commit | `git commit` |

**Le principe :** aucun clic manuel. Tout passe par le code, tout est versionné,
tout est réversible.
