# turtle-box
Bien inspiré par l'outil baptisé [LAN Turtle](https://hakshop.com/collections/lan-turtle/products/lan-turtle?variant=3862428037) de chez [Hak5](https://www.hak5.org/) nous vous proposons de réaliser deux des nombreuses fonctionnalités qu'ils proposent. Pour ce faire nous utiliserons

## Prérequis
Avoir un raspberryPi installé avec l'OS Alpine Linux. ([How to](https://github.com/Lunik/alpine-live-usb))
OU
Une clé bootable raspberryPi avec l'OS Alpine Linux

## Infos
### Package Manager
Gestionaire de paquet: `apk`
install: `apk add`
search: `apk search`
delete: `apk del`

## Schéma

## Partie 1: Brique de base
### Création d'un utilisateur
Création d'un utilisateurs sans mots de passe. Connexion en SSH via une clé SHH.
```sh
$ adduser turtle
$ sudo su - turtle
$ mkdir ~/.ssh/
```
Déposer la clé ssh dans le fichier `/home/turtle/.ssh/authorized_keys`.
Ajouter les droits de **sudo** pour l'utilisateur `turtle`.
```sh
$ apk add sudo
```
Ajouter la ligne suivante dans le fichier de configuration `/etc/sudoers`
```text
turtle ALL=(ALL) NOPASSWD: ALL
```

### Scripts local au démarrage
Pour la suite, il faut activer le daemon `local` pour qu'il lance des scripts présent dans le repertoire `/etc/local.d` au démarrage.
```sh
$ rc-update add local boot
```

### Configuration réseaux
#### Configuration des interfaces
Editer le fichiers de configurations des interfaces `/etc/network/interfaces`
**eth1** étant l'interface connecté au routeur
**eth0** l'interface connecté à la machine cliente 
```text
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
	hostname alpine

auto eth1
iface eth1 inet static
	address 192.168.100.1
	netmask 255.255.255.0
```
Passer les interfaces à `up`
```sh
$ ip link set dev eth0 up
$ ip link set dev eth1 up
```

#### Configuration d'un serveur DHCP
Installer le paquet `dnsmasq` et éditer le fichier de config `/etc/dnsmasq.conf`
```text
interface=eth1
# DHCP
dhcp-range=192.168.100.50,192.168.100.150,255.255.255,1h
## default gateway
dhcp-option=3,192.168.100.1
## dns server
dhcp-option=6,192.168.100.1
```
Redémarrer le service **dhcp**
```sh
$ service dnsmasq restart
```

#### Configuration du NAT
Pour faire en sorte que la machine cliente ait accès à internet.
##### IP Fowarding
Activer l'IP forwarding. Dans le fichier `/etc/sysctl.d/00-alpine.conf` ajouter la ligne
```text
net.ipv4.ip_forward=1
```
Changer l'option dans la configuration courrante
```sh
$ echo "1" > /proc/sys/net/ipv4/ip_forward
```

##### IPTables
Installer le paquet `iptables`
Rajouter un fichier de scripts dans le repertoire des scripts `local`.
`/etc/local.d/nat.start`
```sh
/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
/sbin/iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
```
Rendre ce script executable
```sh
$ chmod +x /etc/local.d/nat.start
```

#### Finalisation
Redémarrer le `turtl box`.
vérifier les iptables
```sh
$ iptables -L
Chain INPUT (policy ACCEPT)
target     prot opt source               destination         

Chain FORWARD (policy ACCEPT)
target     prot opt source               destination         
ACCEPT     all  --  anywhere             anywhere             state RELATED,ESTABLISHED
ACCEPT     all  --  anywhere             anywhere            

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination
```
A partir de maintenant, la machine cliente devrait avoir accès à internet
