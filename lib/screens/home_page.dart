import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_app/models/photo.dart';
import 'package:photo_app/services/api_service.dart';
import 'package:photo_app/services/auth_service.dart';
import 'login_page.dart';
import 'photo_view_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final ImagePicker _picker = ImagePicker();
  List<Photo> _photos = [];
  String? _userName;
  bool _isLoading = false;
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPhotos();
  }

  /// Nom de l'utilisateur connecté (GET /auth/me), affiché dans l'AppBar.
  Future<void> _loadProfile() async {
    final profile = await _authService.getProfile();
    if (mounted && profile != null) {
      setState(() => _userName = profile['name'] as String?);
    }
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final photos = await _apiService.getPhotos();
      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _cleanError(e);
          _isLoading = false;
        });

        // If unauthorized (and the session could not be refreshed), redirect to login
        if (_isUnauthorized(e)) await _logout();
      }
    }
  }

  String _cleanError(Object e) => e.toString().replaceAll('Exception: ', '');

  bool _isUnauthorized(Object e) => e.toString().contains('Unauthorized');

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  /// Choix de la source de la photo : appareil photo ou galerie.
  Future<void> _showImageSourceSheet() async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajouter une photo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choisissez la source de la photo',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 20),
              _SourceTile(
                icon: Icons.photo_camera_outlined,
                color: primaryColor,
                title: 'Prendre une photo',
                subtitle: 'Utiliser l\'appareil photo',
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 12),
              _SourceTile(
                icon: Icons.photo_library_outlined,
                color: Colors.green,
                title: 'Choisir depuis la galerie',
                subtitle: 'Sélectionner une photo existante',
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source != null) await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    XFile? pickedFile;
    try {
      // Compression avant envoi : qualité 80 %, largeur max 1920 px
      pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
    } catch (e) {
      // Permission refusée ou caméra indisponible (ex: simulateur iOS)
      _showSnackBar(
        source == ImageSource.camera
            ? 'Impossible d\'accéder à l\'appareil photo'
            : 'Impossible d\'accéder à la galerie',
        Colors.red,
      );
      return;
    }
    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      await _apiService.uploadPhoto(pickedFile);
      await _loadPhotos();
      _showSnackBar('Photo ajoutée avec succès', Colors.green);
    } catch (e) {
      _showSnackBar('Erreur: ${_cleanError(e)}', Colors.red);
      if (_isUnauthorized(e)) await _logout();
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _openPhoto(Photo photo) async {
    // true : suppression demandée depuis le viewer
    // false : la photo n'existe plus côté serveur -> on recharge la liste
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PhotoViewPage(photo: photo)),
    );
    if (result == true) await _deletePhoto(photo);
    if (result == false) await _loadPhotos();
  }

  Future<void> _deletePhoto(Photo photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la photo'),
        content: const Text('Voulez-vous vraiment supprimer cette photo ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await _apiService.deletePhoto(photo.id);
      await _loadPhotos();
      _showSnackBar('Photo supprimée avec succès', Colors.green);
    } catch (e) {
      _showSnackBar('Erreur: ${_cleanError(e)}', Colors.red);
      if (_isUnauthorized(e)) await _logout();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final showProgressBar = _isUploading || (_isLoading && _photos.isNotEmpty);
    final photosLabel = _photos.isEmpty
        ? 'Aucune photo'
        : '${_photos.length} photo${_photos.length > 1 ? 's' : ''}';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primaryColor, primaryColor.withValues(alpha: 0.75)],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Mes Photos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            const SizedBox(height: 2),
            Text(
              _userName == null ? photosLabel : '$_userName • $photosLabel',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Déconnexion',
          ),
        ],
        // Barre de progression pendant un envoi / rafraîchissement
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: showProgressBar
              ? const LinearProgressIndicator(
                  minHeight: 3,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                )
              : const SizedBox(height: 3),
        ),
      ),
      body: _isLoading && _photos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPhotos,
              child: _buildPhotoGrid(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _showImageSourceSheet,
        tooltip: 'Ajouter une photo',
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_isUploading ? 'Envoi...' : 'Ajouter'),
      ),
    );
  }

  Widget _buildPhotoGrid() {
    if (_errorMessage != null && _photos.isEmpty) {
      return _ScrollableCenter(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 44, color: Colors.red[300]),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[700], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadPhotos,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    if (_photos.isEmpty) {
      return _ScrollableCenter(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Aucune photo',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Appuyez sur "Ajouter" pour prendre ou choisir votre première photo',
              style: TextStyle(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return _PhotoCard(
          photo: photo,
          onTap: () => _openPhoto(photo),
          onDelete: () => _deletePhoto(photo),
        );
      },
    );
  }
}

/// Contenu centré mais scrollable : le "tirer pour rafraîchir"
/// fonctionne aussi sur les écrans vide / erreur.
class _ScrollableCenter extends StatelessWidget {
  final Widget child;

  const _ScrollableCenter({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Vignette d'une photo dans la grille : image, date en bas
/// et bouton rond de suppression en haut à droite.
class _PhotoCard extends StatelessWidget {
  final Photo photo;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PhotoCard({
    required this.photo,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'photo-${photo.id}',
              child: Image.network(
                photo.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.grey[200],
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stack) => Container(
                  color: Colors.grey[200],
                  alignment: Alignment.center,
                  child: Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey[400]),
                ),
              ),
            ),
            // Dégradé + date d'ajout
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        photo.formattedDate,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Zone cliquable : ouvre la photo en plein écran
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _RoundIconButton(
                icon: Icons.delete_outline,
                color: Colors.red,
                background: Colors.white.withValues(alpha: 0.9),
                tooltip: 'Supprimer',
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne du bottom sheet de choix de la source (caméra / galerie).
class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit bouton rond avec fond pastel — utilisé pour l'action supprimer.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? background;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    this.background,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background ?? color.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}
