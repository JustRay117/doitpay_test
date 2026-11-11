# Kubernetes manifest untuk PayTrack API

Manifest ini menjalankan API di EKS cluster dari `infra/`. Validasinya hanya dilakukan secara offline. Tidak ada cluster yang dipakai, sesuai ketentuan asesmen.

Versi bahasa Inggris ada di [README.md](README.md).

## File

| File | Object | Fungsi |
|---|---|---|
| `namespace.yaml` | Namespace `paytrack` | Memisahkan object PayTrack dari workload lain |
| `configmap.yaml` | ConfigMap `paytrack-api-config` | Konfigurasi non-sensitif (`APP_ENV`) |
| `deployment.yaml` | Deployment `paytrack-api` | Menjalankan tiga pod API |
| `service.yaml` | Service `paytrack-api` | Alamat internal yang tetap di depan pod |

Urutan apply di cluster sungguhan: namespace dulu, kemudian sisanya.

## Keputusan

| Keputusan | Alasan |
|---|---|
| Tiga replica | API tetap tersedia ketika satu pod atau satu node gagal |
| Rolling update dengan `maxSurge: 1`, `maxUnavailable: 0` | Pod lama baru dihapus setelah penggantinya ready, jadi rilis yang rusak tidak mengurangi kapasitas |
| Readiness probe ke `/ready` | Pod hanya menerima trafik selama statusnya ready |
| Liveness probe ke `/health` | Container yang macet akan di-restart |
| Request dan limit untuk CPU dan memory | Satu pod tidak bisa menghabiskan resource pod lain di node yang sama |
| Service bertipe `ClusterIP` | API hanya untuk internal, jadi tidak mendapat alamat publik |
| Tag image tetap, tidak pernah `latest` | Versi yang berjalan selalu diketahui, dan rollback punya tujuan yang jelas |
| Hanya `APP_ENV` di ConfigMap | Ini satu-satunya pengaturan yang berbeda di tiap environment. Port tetap memakai default image, yaitu 8080 |

## Asumsi

- Image dibuat dari `Dockerfile` di repository ini dan di-push ke repository Amazon ECR private di akun dan region yang sama. Alamat di `deployment.yaml` adalah placeholder dengan format ECR. Node role dari `infra/` sudah bisa menarik image dari ECR.
- Pemanggil API berada di dalam cluster, atau menjangkau Service lewat gateway internal yang dikelola tim platform. Tidak ada Ingress atau load balancer yang dibuat di sini.
- Request dan limit resource adalah nilai awal. Nilainya tidak diukur.
- API ini tidak punya secret, jadi tidak ada object Secret.

## Validasi tanpa cluster

Jalankan dari root repository:

```bash
docker run --rm -v "$PWD/k8s:/k8s:ro" ghcr.io/yannh/kubeconform:v0.8.0 \
  -strict -summary -verbose -kubernetes-version 1.36.0 /k8s
```

`kubeconform` membandingkan setiap manifest dengan schema resmi Kubernetes versi 1.36, yaitu versi cluster di `infra/`. `-strict` juga menolak field yang tidak dikenal atau salah ketik.

Hasil: `Valid: 4, Invalid: 0, Errors: 0, Skipped: 0`.

Ini membuktikan bahwa manifest-nya tersusun dengan benar. Ini tidak membuktikan bahwa pod bisa berjalan di cluster sungguhan.

Image juga sudah dibuat dan dijalankan secara lokal dengan Docker. `/health`, `/ready` dan `/` menjawab HTTP 200 di port 8080.

## Temuan pada aplikasi yang diberikan

Hal-hal ini tidak diubah, karena pengembangan aplikasi berada di luar scope:

- Image berjalan sebagai root. `Dockerfile` tidak berpindah ke user lain.
- Aplikasi menjalankan development server milik Flask dengan debug mode aktif. Seharusnya dipakai server untuk production.

## Tidak termasuk

Ini adalah rekomendasi, tidak diterapkan, supaya solusinya tetap kecil:

- Security context untuk container: user non-root, file system read-only, tanpa privilege escalation. Security scan melaporkan ketiadaannya dengan severity HIGH; temuan itu diterima di `.trivyignore` beserta alasannya. Tes lokal dengan Docker menunjukkan aplikasi tetap berjalan dengan pengaturan tersebut, jadi risikonya rendah kalau ditambahkan nanti.
- PodDisruptionBudget, supaya maintenance node tidak mematikan semua pod sekaligus.
- NetworkPolicy yang membatasi workload mana yang boleh memanggil API.
- Autoscaling.
