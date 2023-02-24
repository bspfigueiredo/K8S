KUBERNETES INSTALLATION CLUSTER


--------------------------------------------------------------------------------
MASTER AND NODE COMMANDS
--------------------------------------------------------------------------------

# Passar para root e actualizar o reposítório
sudo su

apt-get update
sudo apt install net-tools

apt-get update
sudo apt install nano

apt-get update
sudo apt install vim

# Verificar SWAP
	swapon --show
	#ou
	free -h

# Desligar SWAP
swapoff -a

#Remover img de swap
sudo rm /swap.img 

#remover linha /swap.img       none    swap    sw      0       0 no ficheiro /etc/fstab
nano /etc/fstab


# Update hostname, hostfile e Static IP

	#Atribuir hostname da máquina ao ficheiro
	nano /etc/hostname

	#Ver o IP da máquina
	apt install net-tools
	ifconfig

	#Atribuir os hostnames
	nano /etc/hosts

	#(Config por Interface)Atribuir static IP
	nano /etc/network/interfaces

		# interface(5) file use by ifup(8) and ifdown(8)
		iface enp0s3 inet static #o campo enp03 diz respeito ao interface de rede, este pode ser diferente nos vários serviços hypervisor
			address 192.168.1.24
    		gateway 192.168.1.254  
    		netmask 255.255.248.0
    		dns-search b-simple.local
    		dns-namesevers 192.168.1.211, 192.168.1.210



	# colcoar tab nos nano /etc/hosts

		nano /etc/hosts

		#colocar os vizinhos
			192.168.1.240 controlplane
			192.168.1.241 node1
			192.168.1.242 node2




	#(Config por YAML)Atribuir static IP
	nano /etc/netplan/01-netcfg.yaml

		#dados a copiar
		network:
    		version: 2
    		renderer: networkd
    		ethernets:
        		eth0: #o campo eth0 diz respeito ao interface de rede, este pode ser diferente nos vários serviços hypervisor
					dhcp4: false
            		addresses:
                		- 192.168.1.240/24
            		nameservers:
                		addresses: [192.168.1.211, 192.168.1.210]
            		routes:
                		- to: default
						  via: 192.168.1.254

		#to commit
		sudo netplan apply

		




# Restart servidor
sudo reboot

#0 - Install Packages 
#containerd prerequisites, first load two modules and configure them to load on boot
#https://kubernetes.io/docs/setup/production-environment/container-runtimes/
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF


#Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

#Apply sysctl params without reboot
sudo sysctl --system

#Install containerd
#Verificar versao do containerd vs k8s (https://containerd.io/releases/)
sudo apt-get update 


sudo apt-get install -y containerd ## sai a 1.5.9-0 mas não queremos esta e em baixo vamos corrigir

wget https://github.com/containerd/containerd/releases/download/v1.6.12/containerd-1.6.12-linux-amd64.tar.gz

tar xvf containerd-1.6.12-linux-amd64.tar.gz

systemctl stop containerd

cd bin

cp * /usr/bin/

systemctl start containerd


#Create a containerd configuration file
sudo mkdir -p /etc/containerd

sudo containerd config default | sudo tee /etc/containerd/config.toml


#Set the cgroup driver for containerd to systemd which is required for the kubelet. * ATIVACAO DO CRI
#For more information on this config file see:
# https://github.com/containerd/cri/blob/master/docs/config.md and also
# https://github.com/containerd/containerd/blob/master/docs/ops.md

#At the end of this section
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        ...
#UPDATE: These two lines are now in the default config, you need to change SystemdCgroup = false to SystemdCgroup = true
#          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true

#You can use sed to swap in true
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml


#Verify the change was made
sudo cat /etc/containerd/config.toml

#Restart containerd with the new configuration
sudo systemctl restart containerd

#Install Kubernetes packages - kubeadm, kubelet and kubectl
#Add Google's apt repository gpg key
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - # apt-key is deprecated CHECK trusted.gpd.d

#Add the Kubernetes apt repository
sudo bash -c 'cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF'

#Update the package list and use apt-cache policy to inspect versions available in the repository
sudo apt-get update
apt-cache policy kubelet | head -n 20 

#Verificar versao do containerd vs k8s (https://containerd.io/releases/)
#Install the required packages, if needed we can request a specific version. 
#Use this version because in a later course we will upgrade the cluster to a newer version.
VERSION=1.25.5-00 
sudo apt-get install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION
sudo apt-mark hold kubelet kubeadm kubectl containerd


#To install the latest, omit the version parameters
#sudo apt-get install kubelet kubeadm kubectl
#sudo apt-mark hold kubelet kubeadm kubectl containerd

#1 - systemd Units
#Check the status of our kubelet and our container runtime, containerd.
#The kubelet will enter a crashloop until a cluster is created or the node is joined to an existing cluster.
sudo systemctl status kubelet.service 
sudo systemctl status containerd.service 


#Ensure both are set to start when the system starts up.
sudo systemctl enable kubelet.service
sudo systemctl enable containerd.service

# Validar de novo como ficou
sudo systemctl status kubelet.service 
sudo systemctl status containerd.service 

--------------------------------------------------------------------------------
MASTER
--------------------------------------------------------------------------------

#0 - Creating a Cluster
#Create our kubernetes cluster, specify a pod network range matching that in calico.yaml! 
#Only on the Control Plane Node, download the yaml files for the pod network.

# ESTE DEIXOU DE FUNCIONAR USAR O MEU DE BAIXO
wget https://docs.projectcalico.org/manifests/calico.yaml

# Link do RAW do GITAMOS HUB
wget https://raw.githubusercontent.com/bspfigueiredo/K8S/main/3-Calico/calico.yaml


#Look inside calico.yaml and find the setting for Pod Network IP address range CALICO_IPV4POOL_CIDR, 
#adjust if needed for your infrastructure to ensure that the Pod network IP
#range doesn't overlap with other networks in our infrastructure.
vi calico.yaml

##IMPORTANT UPDATE - 27 Dec 2022##
#kubeadm 1.22 removed the need to use the parameters --config=ClusterConfiguration.yaml and --cri-socket /run/containerd/containerd.sock
#You can now just use kubeadm init to bootstrap the cluster

sudo kubeadm init

# SE DER  erro temos de fazr isto
		apt remove --purge kubelet

		apt install -y kubeadm kubelet=1.25.5-00

		wget https://github.com/containerd/containerd/releases/download/v1.6.12/containerd-1.6.12-linux-amd64.tar.gz
		tar xvf containerd-1.6.12-linux-amd64.tar.gz
		systemctl stop containerd
		cd bin
		cp * /usr/bin/
		systemctl start containerd


		# Voltar a tentar

		sudo kubeadm init


# SE NAO DER ERRO CONTINUAR!
# ele vai dar a key para adicionar os nodes 
# guardar num TXT para mais tarde usar
# confinuar para a parte de baixo



#Before moving on review the output of the cluster creation process including the kubeadm init phases, 
#the admin.conf setup and the node join command


#Configure our account on the Control Plane Node to have admin access to the API server from a non-privileged account.
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#1 - Creating a Pod Network
#Deploy yaml file for your pod network.
kubectl apply -f calico.yaml

#Look for the all the system pods and calico pods to change to Running. 
#The DNS pod won't start (pending) until the Pod network is deployed and Running.
kubectl get pods --all-namespaces


#Gives you output over time, rather than repainting the screen on each iteration.
kubectl get pods --all-namespaces --watch


#All system pods should be Running
kubectl get pods --all-namespaces


#Get a list of our current nodes, just the Control Plane Node/Master Node...should be Ready.
kubectl get nodes 


#Alterar o tipo de encapsulamento da rede do calico(comunicação entre várias redes).
#Por defeito, o calico instala com o modo IPIPMode - Always. Esta configuração é ideal para sistemas on premise.
#Caso a instalação seja na cloud(Azure/Google/etc...) é necessário alterar a configuração da IPPool para VXLANMODE - Always e IPIPMode - Never

#Instalar o CLI do calico de preferência em /usr/local/bin/ (na PATH)

cd /usr/local/bin/
curl -L https://github.com/projectcalico/calico/releases/download/v3.24.0/calicoctl-linux-amd64 -o calicoctl
chmod +x ./calicoctl

#Obter o ficheiro -yaml com a configuração da IPPool. A opção --allow-version-mismatch é para usar quando a versão do cliente é diferente da versão do cluster do calico.
calicoctl get ippool --allow-version-mismatch -o yaml

# guardar o conteudo num txt para usar na linha seguinte
# exemplo
apiVersion: projectcalico.org/v3
items:
- apiVersion: projectcalico.org/v3
  kind: IPPool
  metadata:
    creationTimestamp: "2023-02-24T10:39:29Z"
    name: default-ipv4-ippool
    resourceVersion: "1267"
    uid: 7cd1d931-2be9-4e0b-8bea-d48f7ca80322
  spec:
    allowedUses:
    - Workload
    - Tunnel
    blockSize: 26
    cidr: 172.16.0.0/16
    ipipMode: Always
    natOutgoing: true
    nodeSelector: all()
    vxlanMode: Never
kind: IPPoolList
metadata:
  resourceVersion: "1436"


#Alterar o ficheiro com o resultado do yaml da linha anterior.
nano pools.yaml

#Aplicar as alterações
calicoctl apply -f pools.yaml --allow-version-mismatch

#2 - systemd Units...again!
#Check out the systemd unit...it's no longer crashlooping because it has static pods to start
#Remember the kubelet starts the static pods, and thus the control plane pods
sudo systemctl status kubelet.service 


#3 - Static Pod manifests
#Let's check out the static pod manifests on the Control Plane Node
ls /etc/kubernetes/manifests


#And look more closely at API server and etcd's manifest.
sudo more /etc/kubernetes/manifests/etcd.yaml
sudo more /etc/kubernetes/manifests/kube-apiserver.yaml


#Check out the directory where the kubeconfig files live for each of the control plane pods.
ls /etc/kubernetes




# No Master executar o seguinte comando para obter o comando join
kubeadm token create --print-join-command


--------------------------------------------------------------------------------
NODES
--------------------------------------------------------------------------------

#IR AOS  NODES E EXECUTAR O COMANDO DEVOLVIDO PELO COMANDO ANTERIOR

kubeadm join 192.168.1.240:6443 --token 3ehm19.cbki2coahrxuf7kn --discovery-token-ca-cert-hash sha256:11c318ff37db3f0f3caaecba74f85de889f993d9de6407cb369c352fc7679aa5


Exemplo :
sudo kubeadm join 10.164.0.19:6443 --token 6gzan7.3vfyo09owxbuf5hp --discovery-token-ca-cert-hash sha256:3e499390beeed383d173e2eab32272340057e4827e4f3cf10a87647decff397a


# se pretendermos aceder ao master node através do worker node executar o seguinte comando que copia o ficheiro /etc/kubernetes/admin.conf para o worker node $HOME/.kube/config.
# Desta forma, o worker node conhece as configurações do master e já pode aceder ao API Server
#mkdir -p $HOME/.kube
#sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#sudo chown $(id -u):$(id -g) $HOME/.kube/config

# mudar o IP para o nosso ip do Master
scp -r bsimple@192.168.1.240:/home/kmaster/.kube .

# Não fizemos no nosso! caso seja preciso fazemos

scp -r kmaster@10.164.0.19:/home/kmaster/.kube .


--------------------------------------------------------------------------------
MASTER -- Instalar o ARGOCD
--------------------------------------------------------------------------------

kubectl create namespace argocd

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'


#Instalar o METAL LB para dar usar os ips de 236 a 239

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml 


>> agora ir mudar os yamls do metal lb (sao 2) no ipaddresspool meter a range de ips que podemos usar

>> meter os ficheiros na maquina numa pasta "MetalLB"


# criar
kubectl apply -f ipaddresspool.yaml

kubectl apply -f l2advertisement.yaml

# validar que ja tem ip externo

kubectl get services --all-namespaces 


## este passo não é preciso apenas para quando não temos o metal lb a funcionar
kubectl port-forward service/argocd-server 8080:80 -n argocd



# Saber a apssword do argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# >> password desencriptada, mudar no primeiro login
Ijnuju5NYrtfdu1T


# configurar o argo

# ligar a um repositorio GIFHUB
https://github.com/bspfigueiredo/K8S.git


#Ir buscar secret
# settings na imagem do canto superior direito
# Developer settings em baixo de todo à esquerda
# depois Personal access tokens >> Tokens (classic)
# generate new token
# Generate new token (Beta)
# atibuir nome e as permisoes todas
# guardar o token

# em vez de username e pass meter o token gerado nunca expira com acesso a tudo
VIA: HTTPS
Type: GIT
Project: default
repositorio url: https://github.com/bspfigueiredo/K8S.git
username: bspfigueiredo
password: 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




#Criar volume persistente
#Criamos um Persistent Volume
wget https://raw.githubusercontent.com/bspfigueiredo/K8S/main/8-PersistentVolume/persistentvolume.yaml
kubectl create -f persistentvolume.yaml
kubectl get pv


kubectl apply -f https://k8s.io/examples/pods/storage/pv-claim.yaml
kubectl get pv

#instalar ingress nginx / grafana / .... pelo HELM


Instalação e configuração a partir do ArgoCD usando HELM:

Repositorio GIT HUB: https://github.com/bspfigueiredo/K8S.git


Instalado:

Helm: >> https://charts.bitnami.com/bitnami

>> Ingress Controller
>> Redis
>> Grafana
>> Postgressql
>> RabbitMQ


Prometheus: >> https://prometheus-community.github.io/helm-charts

OpenEBS: >> https://openebs.github.io/charts




Ainda não instalado:

Isitio: >> https://istio-release.storage.googleapis.com/charts

Elastic: >> https://helm.elastic.co





# Instalação do site do Cardoso
pelo argo com os yaml no GIT



#colocar o prometheus e o grafana e os outros com ip para aceder a eles
# alterar os comandos conforme as necessidades estes sao exemplos do argo
kubectl patch svc grafana -n grafana -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc rabbitmq -n rabbitmq -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'