# Terraform: EKS cluster untuk PayTrack

Folder ini membuat satu Amazon EKS cluster dan satu managed node group di dalam VPC yang sudah ada. Validasinya hanya dilakukan secara offline. Tidak ada yang di-apply, sesuai ketentuan asesmen.

Versi bahasa Inggris ada di [README.md](README.md).

## Yang dibuat

| Resource | Fungsi |
|---|---|
| `aws_iam_role.cluster` + 1 policy attachment | Role yang dipakai EKS control plane (`AmazonEKSClusterPolicy`) |
| `aws_eks_cluster.this` | Cluster, di private subnet yang sudah ada, dengan API endpoint private saja |
| `aws_iam_role.node` + 3 policy attachment | Role yang dipakai worker node |
| `aws_eks_node_group.this` | Managed node group di private subnet yang sama |

Semuanya ditulis sebagai resource biasa, tanpa module, sehingga pengaturan cluster, node group, IAM dan network terlihat langsung di `main.tf`.

| File | Isi |
|---|---|
| `versions.tf` | Versi Terraform dan AWS provider |
| `variables.tf` | Input |
| `main.tf` | Provider, IAM role, cluster, node group |
| `outputs.tf` | Nama cluster, endpoint, security group ID, ARN node role |
| `terraform.tfvars.example` | Contoh input dengan placeholder, tanpa kredensial |

## Versi

- AWS provider `~> 6.0`: semua rilis 6.x, tidak pernah major version baru. Lock file mengunci versi yang sudah dites, yaitu 6.72.0.
- Terraform `>= 1.5.0`. Hanya dites dengan 1.17.1.
- Kubernetes `1.36` di file contoh. Pada 11 November 2026 versi ini masuk EKS standard support sampai 2 Agustus 2027, dan bukan rilis terbaru.

## Asumsi

### Network

- VPC dan private subnet sudah ada dan dikelola tim platform. Kode ini tidak membuat atau mengubahnya.
- `private_subnet_ids` berisi minimal dua subnet di Availability Zone yang berbeda. Ini syarat dari EKS.
- Subnet punya cukup alamat IP kosong. Setiap pod mendapat alamat IP sendiri dari subnet.
- Private subnet punya jalur keluar ke layanan AWS, lewat NAT gateway atau VPC endpoint. Node membutuhkannya untuk bergabung ke cluster dan menarik image. Tanpa itu, pembuatan node group gagal.
- Kode ini tidak membutuhkan tag pada subnet. Kalau nanti ditambahkan internal load balancer, subnet perlu tag `kubernetes.io/role/internal-elb = 1`.
- `vpc_id` adalah input, tetapi tidak ada resource yang memakainya. EKS mengetahui VPC dari subnet ID. Variable ini dipertahankan karena ada di file contoh yang diberikan.

### Akses cluster

- Kubernetes API endpoint private saja. Ini cocok untuk API internal. Untuk memakai `kubectl`, seseorang harus berada di dalam VPC, lewat VPN atau bastion host, dan cluster security group harus mengizinkan port 443 dari sumber tersebut. Karena itu security group ID dijadikan output.
- Runner milik GitHub tidak bisa menjangkau endpoint private. Karena itu workflow CI hanya memvalidasi dan tidak melakukan deploy.
- Authentication mode adalah `API`. Identitas IAM yang membuat cluster menjadi administratornya. Orang lain tidak punya akses sampai diberi EKS access entry. Tidak ada access entry yang dibuat di sini.
- Kredensial AWS berasal dari environment orang yang menjalankan Terraform. Tidak ada key di dalam file-file ini.

### Akses node

- Node berjalan di private subnet dan tidak bisa dijangkau dari internet.
- SSH ke node tidak dibuka. Node group tidak memiliki blok `remote_access`.

### IAM

- Kedua role hanya memakai AWS-managed policy. Tidak ada custom policy atau policy administrator yang dipasang.
- Node role memakai `AmazonEC2ContainerRegistryPullOnly`, yang lebih sempit daripada policy `ReadOnly` yang lama.
- `AmazonEKS_CNI_Policy` dipasang di node role karena itu pengaturan paling sederhana yang berfungsi. AWS menyarankan role terpisah untuk network plugin. Lihat "Tidak termasuk".

## Validasi tanpa membuat resource cloud

Jalankan dari folder ini:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

| Command | Yang dicek |
|---|---|
| `fmt -check` | Format. Tidak menampilkan apa-apa kalau sudah benar. |
| `init -backend=false` | Mengunduh provider. Penyimpanan state dilewati, jadi tidak butuh akun AWS. |
| `validate` | Syntax, referensi dan nama argumen. Tidak menghubungi AWS. |

Ketiganya lolos.

### Opsional: plan offline

`terraform plan` biasanya butuh kredensial AWS. Plan tetap bisa dijalankan secara offline dengan kredensial palsu dan satu file override lokal yang mematikan pengecekan kredensial pada provider. File itu di-ignore oleh git dan bukan bagian dari submission ini.

`offline_override.tf`:

```hcl
provider "aws" {
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
```

```bash
AWS_ACCESS_KEY_ID=fake AWS_SECRET_ACCESS_KEY=fake \
  terraform plan -var-file=terraform.tfvars.example
```

Hasil: `Plan: 8 to add, 0 to change, 0 to destroy.`

Plan ini tidak pernah menghubungi AWS. Plan menunjukkan apa yang akan dibuat Terraform, tetapi tidak bisa memastikan bahwa subnet-nya ada atau bahwa akun punya izin yang dibutuhkan. Konfigurasi ini terbukti valid; belum terbukti berhasil di-apply di akun asli.

## Tidak termasuk

Ini adalah rekomendasi, tidak diterapkan, supaya solusinya tetap kecil:

- Remote state backend, misalnya S3. Ini dibutuhkan sebelum dipakai sungguhan.
- Control plane logging dan enkripsi secret dengan KMS key milik sendiri.
- IAM role terpisah untuk network plugin, supaya CNI policy bisa dilepas dari node role.
- Access entry untuk tim platform.
