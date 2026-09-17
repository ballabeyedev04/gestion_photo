import 'package:flutter/material.dart';
import 'package:photo_app/models/photo.dart';
import 'package:photo_app/services/api_service.dart';

/// Affichage plein écran d'une photo (zoom au pincement).
///
/// Valeur renvoyée par Navigator.pop :
///  - `true`  : l'utilisateur demande la suppression (HomePage confirme et appelle l'API)
///  - `false` : la photo n'existe plus côté serveur (HomePage recharge la liste)
///  - `null`  : simple retour
class PhotoViewPage extends StatefulWidget {
  final Photo photo;

  const PhotoViewPage({super.key, required this.photo});

  @override
  State<PhotoViewPage> createState() => _PhotoViewPageState();
}

class _PhotoViewPageState extends State<PhotoViewPage> {
  final ApiService _apiService = ApiService();
  late Photo _photo = widget.photo;

  @override
  void initState() {
    super.initState();
    _refreshPhoto();
  }

  /// Recharge la photo depuis l'API (GET /photos/:id) : infos à jour et détection
  /// d'une photo supprimée entre-temps (ex: depuis un autre appareil).
  Future<void> _refreshPhoto() async {
    try {
      final photo = await _apiService.getPhoto(widget.photo.id);
      if (mounted) setState(() => _photo = photo);
    } catch (e) {
      if (!mounted) return;
      // Autres erreurs (réseau...) : on garde les infos déjà affichées
      if (!e.toString().contains('Photo not found')) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cette photo n\'existe plus'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: 'photo-${widget.photo.id}',
                    child: Image.network(
                      _photo.url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const CircularProgressIndicator(color: Colors.white);
                      },
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.broken_image_outlined,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: Colors.white.withValues(alpha: 0.06),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    _photo.formattedDate,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                  if (_photo.formattedSize.isNotEmpty) ...[
                    const Icon(Icons.sd_storage_outlined, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      _photo.formattedSize,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
