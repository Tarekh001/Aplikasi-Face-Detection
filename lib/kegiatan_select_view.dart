import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'presensi_kegiatan_view.dart';

/// Screen to select an active kegiatan from today's list.
/// Navigates to PresensiKegiatanView upon selection.
class KegiatanSelectView extends StatefulWidget {
  const KegiatanSelectView({super.key});

  @override
  State<KegiatanSelectView> createState() => _KegiatanSelectViewState();
}

class _KegiatanSelectViewState extends State<KegiatanSelectView> {
  List<Map<String, dynamic>> _kegiatanList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchKegiatan();
  }

  Future<void> _fetchKegiatan() async {
    final list = await ApiService.fetchActiveKegiatan();
    if (mounted) {
      setState(() {
        _kegiatanList = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.shortestSide;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0057A4), Color(0xFF003366)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.all(s * 0.05),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: EdgeInsets.all(s * 0.025),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(s * 0.03),
                          ),
                          child: Icon(Icons.arrow_back, color: Colors.white, size: s * 0.06),
                        ),
                      ),
                      SizedBox(width: s * 0.04),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pilih Kegiatan',
                              style: TextStyle(fontSize: s * 0.055, fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('Kegiatan aktif hari ini',
                              style: TextStyle(fontSize: s * 0.03, color: Colors.white70)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () { setState(() => _isLoading = true); _fetchKegiatan(); },
                        icon: Icon(Icons.refresh, color: Colors.white, size: s * 0.06),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _kegiatanList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_busy, size: s * 0.15, color: Colors.white38),
                              SizedBox(height: s * 0.03),
                              Text('Tidak ada kegiatan aktif\nhari ini',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: s * 0.04, color: Colors.white54)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: s * 0.05),
                          itemCount: _kegiatanList.length,
                          itemBuilder: (context, index) {
                            final k = _kegiatanList[index];
                            return _KegiatanCard(
                              data: k,
                              shortestSide: s,
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => PresensiKegiatanView(
                                    kegiatanId: k['id'] as int,
                                    kegiatanName: k['nama_kegiatan']?.toString() ?? '',
                                  ),
                                ));
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KegiatanCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final double shortestSide;
  final VoidCallback onTap;

  const _KegiatanCard({required this.data, required this.shortestSide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = shortestSide;
    final isGlobal = data['is_global'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: s * 0.035),
        padding: EdgeInsets.all(s * 0.045),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(s * 0.04),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: s * 0.02, offset: Offset(0, s * 0.01))],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: s * 0.14,
              height: s * 0.14,
              decoration: BoxDecoration(
                color: isGlobal ? const Color(0xFF7C3AED).withValues(alpha: 0.1) : const Color(0xFF0057A4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(s * 0.03),
              ),
              child: Icon(
                isGlobal ? Icons.public : Icons.business,
                size: s * 0.07,
                color: isGlobal ? const Color(0xFF7C3AED) : const Color(0xFF0057A4),
              ),
            ),
            SizedBox(width: s * 0.04),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['nama_kegiatan']?.toString() ?? '-',
                    style: TextStyle(fontSize: s * 0.038, fontWeight: FontWeight.bold, color: Colors.black87)),
                  SizedBox(height: s * 0.01),
                  if (data['alamat_lokasi'] != null && data['alamat_lokasi'].toString().isNotEmpty)
                    Row(children: [
                      Icon(Icons.location_on, size: s * 0.03, color: Colors.grey),
                      SizedBox(width: s * 0.01),
                      Expanded(child: Text(data['alamat_lokasi'].toString(),
                        style: TextStyle(fontSize: s * 0.028, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  SizedBox(height: s * 0.008),
                  Row(children: [
                    Icon(Icons.access_time, size: s * 0.03, color: Colors.grey),
                    SizedBox(width: s * 0.01),
                    Text('${data['jam_mulai'] ?? '-'} - ${data['jam_selesai'] ?? '-'}',
                      style: TextStyle(fontSize: s * 0.028, color: Colors.grey[600])),
                    SizedBox(width: s * 0.03),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: s * 0.02, vertical: s * 0.005),
                      decoration: BoxDecoration(
                        color: isGlobal ? const Color(0xFF7C3AED).withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(s * 0.02),
                      ),
                      child: Text(isGlobal ? 'GLOBAL' : 'INTERNAL',
                        style: TextStyle(fontSize: s * 0.022, fontWeight: FontWeight.bold,
                          color: isGlobal ? const Color(0xFF7C3AED) : Colors.amber[800])),
                    ),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: s * 0.06, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
