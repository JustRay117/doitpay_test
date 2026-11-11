# Diagnosis: intermittent 5xx setelah rilis 10:05

Diagnosis ini hanya berdasarkan `incident.md`. Tidak ada cluster yang tersedia, jadi command di bawah adalah yang akan saya jalankan, bukan yang sudah saya jalankan.

## Kronologi

| Waktu | Kejadian |
|---|---|
| 10:05 | Versi baru dirilis. |
| 10:07:41 | Readiness probe gagal dengan HTTP 503. Artinya aplikasi sempat menjawab koneksi. Kalau aplikasinya crash, koneksi akan ditolak (connection refused). |
| 10:07:53 | Terjadi `Back-off restarting failed container`. |
| 10:08:04 | Log: `downstream reconciliation service unavailable`, kemudian `server startup aborted`. |
| 10:08 | Gateway internal melaporkan intermittent 5xx. Sebagian request user sukses, sebagian gagal. |

## Hipotesis

Aplikasi versi terbaru melakukan pengecekan ke downstream service (service lain yang dibutuhkan) ketika startup. Ketika service tersebut tidak bisa dijangkau, aplikasi melakukan abort, container exit, lalu di-restart oleh Kubernetes secara berulang (loop).

### `Running` belum tentu siap

Meskipun pods terlihat `Running`, yang perlu dilihat adalah kolom `READY` dan `RESTARTS`:

- `READY 1/1` berarti pod benar-benar siap menerima trafik.
- `READY 0/1` berarti pod belum siap atau gagal.
- `RESTARTS` yang terus bertambah berarti container mengalami restart loop.

### Yang belum terjelaskan

Pod yang gagal readiness seharusnya dikeluarkan dari Service dan tidak menerima trafik. Tetapi user tetap menerima error 5xx.

Kemungkinan utamanya: pod baru sempat lolos readiness dan menerima trafik, kemudian gagal melayani request karena downstream service yang dibutuhkan tidak stabil atau tidak bisa dijangkau. Ini masih dugaan dan perlu dibuktikan dengan pengecekan nomor 1, 5 dan 7 di bawah.

## Evidence yang akan diambil

```bash
# 1. Cek pods yang ready atau tidak ready, jumlah restart, dan versinya
kubectl get pods -n paytrack -o wide
kubectl get replicasets -n paytrack

# 2. Cek status rollout
kubectl rollout status -n paytrack deployment/paytrack-api --timeout=10s

# 3. Cek alasan container berhenti (exit code, Error atau OOMKilled) dan events pada pod
kubectl describe pod -n paytrack paytrack-api-xxxxxxxxxx-xxxxx

# 4. Cek logs pada container yang crash
kubectl logs -n paytrack paytrack-api-xxxxxxxxxx-xxxxx --previous

# 5. Ke pod mana Service mengirim trafik saat ini?
kubectl -n paytrack get endpointslices -l kubernetes.io/service-name=paytrack-api

# 6. Cek recent events
kubectl -n paytrack get events --sort-by=.lastTimestamp

# 7. Test apakah healthy pod bisa menjangkau downstream service
kubectl -n paytrack exec <healthy-pod> -- python -c "import socket; socket.create_connection(('<downstream-host>', <port>), 3)"

# 8. Cek resource usage
kubectl -n paytrack top pods
```

## Kapan rollback

Rollback dilakukan ketika pengecekan 1 sampai 4 menunjukkan bahwa masalahnya ada di versi terbaru:

- Aplikasi versi terbaru exit dengan error code.
- Pod versi terbaru `READY 0/1`.
- `describe pod` dan logs menunjukkan error, atau pod tertahan di `Pending`.

User sudah terdampak dan image versi sebelumnya masih tersedia, jadi rollback tidak perlu menunggu root cause lengkap.

```bash
kubectl -n paytrack rollout undo deployment/paytrack-api
```

Setelah rollback, pastikan semua pods `READY 1/1` dan intermittent error 5xx sudah tidak ada.

## Pencegahan

- **`maxUnavailable: 0` pada Deployment**, sehingga pods lama tetap dipertahankan sampai pods baru sudah ready. Ini sudah diterapkan di `k8s/deployment.yaml`.
- **Menambahkan `minReadySeconds`**, sehingga pod baru harus tetap ready selama beberapa detik sebelum rollout dilanjutkan. Pod yang lolos readiness sebentar lalu gagal lagi tidak akan dianggap berhasil.
- **Test pada environment yang juga memiliki downstream service**, supaya masalah koneksi ke downstream terlihat sebelum rilis ke cluster utama.
