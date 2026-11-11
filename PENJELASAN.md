# Penjelasan Pendekatan (Part E)

Dokumen ini merangkum cara saya mengerjakan asesmen PayTrack.

## Isi submission

| Part | Isi | Lokasi |
|---|---|---|
| A | Terraform untuk EKS cluster, managed node group dan IAM | [infra/](infra/), penjelasan di [infra/READ_INFRA.md](infra/READ_INFRA.md) |
| B | Namespace, ConfigMap, Deployment, Service | [k8s/](k8s/), penjelasan di [k8s/READ_K8S.md](k8s/READ_K8S.md) |
| C | Workflow validasi untuk pull request | [.github/workflows/validate.yml](.github/workflows/validate.yml), [.trivyignore](.trivyignore) |
| D | Diagnosis insiden 5xx | [diagnosis_indonesia.md](troubleshooting/diagnosis_indonesia.md) (Bahasa Indonesia), [diagnosis.md](troubleshooting/diagnosis.md) (English) |
| E | Penjelasan pendekatan | Dokumen ini |

## 1. Keputusan desain utama dan asumsi

Prinsip yang saya pakai: solusi sekecil mungkin yang memenuhi permintaan, dan setiap baris harus bisa saya jelaskan. Dokumen asesmen menyebut bahwa prioritas dan alasan lebih penting daripada jumlah kontrol.

### Keputusan

| Area | Keputusan | Alasan |
|---|---|---|
| Terraform | Resource biasa, tanpa module | Konfigurasi cluster, node group, IAM dan network terlihat langsung di `main.tf` |
| Terraform | Provider AWS `~> 6.0`, dikunci di 6.72.0 lewat lock file | Update hanya dalam major version yang sudah dites |
| Terraform | Region lewat variable `aws_region`, tanpa default | Region hanya ditulis di satu tempat dan harus dipilih secara sadar |
| EKS | API endpoint private saja | PayTrack adalah API internal, jadi tidak ada alasan membuka akses dari internet |
| EKS | `authentication_mode = "API"` | Akses cluster diberikan per identitas IAM. Awalnya hanya pembuat cluster yang menjadi admin |
| Node | Managed node group di private subnet, tanpa SSH | AWS yang mengelola instance. Node tidak bisa dijangkau dari internet |
| IAM | Hanya AWS-managed policy, tanpa policy admin | Sesuai dokumentasi AWS dan mudah dipelihara tim kecil |
| Kubernetes | 3 replica, rolling update dengan `maxUnavailable: 0` | Pod lama tidak dihapus sebelum pod baru ready |
| Kubernetes | Readiness probe ke `/ready`, liveness probe ke `/health` | Memakai endpoint yang sudah ada di aplikasi |
| Kubernetes | Service `ClusterIP` | Tidak ada alamat publik |
| CI | Tiga job terpisah: Terraform, manifest, security scan | Kalau gagal, langsung terlihat pengecekan mana yang gagal |
| CI | `permissions: contents: read`, tanpa kredensial AWS, tanpa deploy | Validasi terpisah dari deployment |

### Asumsi

- VPC dan private subnet sudah ada dan dikelola tim platform. Subnet punya jalur keluar ke layanan AWS (NAT gateway atau VPC endpoint).
- Engineer menjangkau endpoint private lewat VPN atau bastion di dalam VPC.
- Image dibuat dari `Dockerfile` di repo ini dan di-push ke Amazon ECR private. Alamat image di Deployment adalah placeholder, karena dokumen tidak menyebut image atau registry.
- Pemanggil API berada di dalam cluster, atau lewat gateway internal milik tim platform.
- Angka CPU dan memory di Deployment adalah nilai awal, bukan hasil pengukuran.

Daftar lengkap ada di [infra/README.md](infra/README.md) dan [k8s/README.md](k8s/README.md).

## 2. Validasi tanpa membuat resource cloud

Semua pengecekan berjalan secara lokal. Tidak ada akun AWS atau cluster yang dipakai.

| Pengecekan | Yang dibuktikan | Hasil |
|---|---|---|
| `terraform fmt -check -recursive` | Format benar | Lolos |
| `terraform init -backend=false` | Provider bisa diunduh tanpa akun AWS | Lolos |
| `terraform validate` | Syntax, referensi dan nama argumen benar | `Success! The configuration is valid.` |
| `terraform plan` offline (kredensial palsu, lihat [infra/README.md](infra/README.md)) | Daftar resource yang akan dibuat sesuai harapan | `Plan: 8 to add, 0 to change, 0 to destroy.` |
| `kubeconform` v0.8.0, schema Kubernetes 1.36 | Manifest sesuai schema resmi | `Valid: 4, Invalid: 0` |
| Trivy 0.76.2, `--severity HIGH,CRITICAL` | Tidak ada temuan HIGH atau CRITICAL di luar yang diterima | Lolos, lihat catatan di bawah |
| `actionlint` | File workflow benar secara syntax | Lolos |
| `docker build` dan `docker run` | Image bisa dibuat. `/health`, `/ready` dan `/` menjawab HTTP 200 di port 8080 | Lolos |

**Catatan Trivy:** tanpa ignore file, Trivy melaporkan 21 temuan: 5 HIGH, 9 MEDIUM, 7 LOW, 0 CRITICAL. Kelima temuan HIGH saya terima dengan alasan tertulis di [.trivyignore](.trivyignore). Tidak ada yang saya perbaiki di kode. Alasannya ada di bagian 3.

**Yang tidak terbukti:** pengecekan di atas membuktikan bahwa file-nya valid. Pengecekan itu tidak membuktikan bahwa `terraform apply` berhasil di akun asli, atau bahwa pod benar-benar berjalan di cluster.

## 3. Trade-off keamanan dan operasional

| Pilihan | Yang didapat | Harga yang dibayar |
|---|---|---|
| Endpoint EKS private saja | API cluster tidak terbuka ke internet | Butuh VPN atau bastion. Runner GitHub tidak bisa menjangkau cluster, jadi deploy otomatis butuh runner di dalam VPC |
| Resource biasa, tanpa module | Semua terlihat dan mudah dijelaskan | Fitur tambahan harus ditulis sendiri |
| `AmazonEKS_CNI_Policy` di node role | Satu baris, langsung jalan | AWS menyarankan role terpisah untuk network plugin. Dengan cara ini izin tersebut melekat pada node |
| Tanpa security context di Deployment | Manifest tetap kecil | Container berjalan sebagai root. Dua temuan HIGH diterima, tidak diperbaiki |
| Tanpa enkripsi secret dengan KMS key sendiri | Tidak perlu resource KMS | Satu temuan HIGH diterima. PayTrack tidak menyimpan Kubernetes secret |
| Gate Trivy hanya HIGH dan CRITICAL | Workflow tidak gagal karena hal kecil | Temuan MEDIUM dan LOW hanya terlihat di log, contohnya control plane logging |
| Temuan diterima lewat `.trivyignore` | Setiap pengecualian tertulis dan punya alasan | Daftar ini harus ditinjau ulang supaya tidak terlupakan |
| `maxUnavailable: 0` | Rilis yang rusak tidak mengurangi kapasitas | Rollout lebih lambat dan butuh ruang untuk satu pod tambahan |
| Versi tool dikunci dengan tag | Sederhana dan hasilnya konsisten | Mengunci dengan commit SHA atau digest lebih aman terhadap perubahan di sisi penyedia. Itu rekomendasi, belum diterapkan |
| State Terraform lokal | Tidak perlu resource tambahan untuk asesmen | Tim tidak bisa bekerja bersama. Remote backend wajib ada sebelum dipakai sungguhan |

## 4. Yang belum selesai dan alasannya

| Hal | Status | Alasan |
|---|---|---|
| Workflow berjalan di GitHub Actions | Belum dijalankan saat dokumen ini ditulis. File lolos `actionlint`, dan command yang sama lolos secara lokal | Workflow baru berjalan setelah ada pull request di repository yang memuat `.github/workflows/` di root |
| `terraform apply` dan `plan` dengan akun asli | Tidak dilakukan | Dilarang oleh asesmen, dan tidak ada kredensial |
| Security context pada container | Rekomendasi, tidak diterapkan | Tidak diwajibkan. Saya memilih menjaga solusi tetap kecil. Tes lokal dengan Docker menunjukkan aplikasi tetap jalan sebagai user non-root dengan file system read-only, jadi risikonya rendah kalau ditambahkan nanti |
| Otomatisasi deployment | Tidak dibuat | Opsional. Usulan singkat ada di bawah tabel ini |
| Remote state, control plane logging, enkripsi KMS, role terpisah untuk CNI, access entry untuk tim | Rekomendasi, tidak diterapkan | Menjaga solusi tetap kecil. Lihat [infra/README.md](infra/README.md) |
| PodDisruptionBudget, NetworkPolicy, autoscaling | Rekomendasi, tidak diterapkan | Sama. Lihat [k8s/README.md](k8s/README.md) |
| Temuan pada aplikasi: image berjalan sebagai root, Flask debug mode aktif | Dilaporkan, tidak diperbaiki | Pengembangan aplikasi di luar scope asesmen |

**Usulan deployment, kalau nanti dibutuhkan:** workflow terpisah dari validasi. Autentikasi ke AWS memakai OIDC dari GitHub untuk mengambil IAM role dengan kredensial berumur pendek, tanpa access key jangka panjang. Role itu hanya boleh dipakai oleh repository dan environment ini. GitHub Environment diberi required reviewers sebagai approval. Karena endpoint cluster private, runner harus berada di dalam VPC.

## 5. Penggunaan AI dan alat lain

Saya mengerjakan asesmen ini bersama Claude Code, asisten AI dari Anthropic.

**Pembagian peran:**

- AI menyusun draft file Terraform, manifest, workflow dan dokumentasi, satu langkah kecil setiap kali, disertai penjelasan.
- Saya menentukan arah, mempertanyakan saran, mengambil keputusan, dan menjalankan ulang command validasi.
- Draft diagnosis versi bahasa Indonesia saya tulis sendiri. AI merapikan formatnya, mengoreksi beberapa hal, dan menambahkan tabel pembeda jenis masalah.

**Saran yang diverifikasi, dipertanyakan, atau ditolak:**

| Jenis | Kasus | Hasil |
|---|---|---|
| Diverifikasi | Versi Kubernetes. Versi tidak diambil dari ingatan AI, tetapi dicek ke dokumentasi AWS pada 11 November 2026 | Standard support mencakup 1.34 sampai 1.37. Dipilih 1.36: bukan rilis terbaru, dan didukung sampai 2 Agustus 2027 |
| Diverifikasi | Policy ECR untuk node role. Banyak contoh memakai `AmazonEC2ContainerRegistryReadOnly` | Halaman AWS tentang node IAM role menyebut `AmazonEC2ContainerRegistryPullOnly`, yang lebih sempit. Itu yang dipakai. Halaman yang sama menyarankan role terpisah untuk CNI policy; ini dicatat sebagai trade-off |
| Ditolak | AI menyarankan dan sempat menambahkan `securityContext` ke Deployment untuk memperbaiki temuan Trivy | Saya menghapusnya, karena tidak diwajibkan dan saya ingin solusi tetap kecil. Akibatnya temuan itu diterima di `.trivyignore` dengan alasan tertulis |
| Dipertanyakan | Saya menanyakan AI apakah menjalankan `terraform plan` melanggar aturan asesmen? | Dicek terhadap tiap aturan di dokumen: tidak melanggar, selama tidak ada kredensial asli dan file override tidak di-commit |
| Dipertanyakan | Alamat image di Deployment dibuat oleh AI dan tidak ada di dokumen asesmen | Dipertahankan sebagai placeholder dan ditulis sebagai asumsi |

**Alat lain:** Terraform 1.17.1, kubeconform v0.8.0, Trivy 0.76.2, actionlint, Docker. Nomor versi provider dan tool diambil dari sumber resminya (Terraform Registry dan halaman rilis GitHub), bukan dari ingatan AI.
