import 'package:flutter/material.dart';
import 'package:fijkplayer/fijkplayer.dart';
import 'package:flutter_ijk_pro/log_utils.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  static const String TAG = 'TestVideoPage';

  String get videoUrl => "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8";

  FijkPlayer? _player;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    LogD(tag: TAG, 'Initializing player: $videoUrl');

    // 清理之前的播放器
    _player?.release();
    _player = null;

    try {
      _player = FijkPlayer();

      // 设置播放器选项
      _player!.setOption(FijkOption.playerCategory, "enable-accurate-seek", 1);
      _player!.setOption(FijkOption.playerCategory, "mediacodec", 1);
      _player!.setOption(FijkOption.playerCategory, "packet-buffering", 0);
      _player!.setOption(FijkOption.formatCategory, "reconnect", 1);
      _player!.setOption(FijkOption.formatCategory, "timeout", 20000000);
      _player!.setOption(
          FijkOption.formatCategory, "user_agent", "Flutter FijkPlayer");

      // 监听播放器状态
      _player!.addListener(_playerListener);

      // 设置数据源并准备播放
      _player!.setDataSource(videoUrl, autoPlay: false).then((_) {
        LogD(tag: TAG, 'Data source set successfully');
        return _player!.prepareAsync();
      }).then((_) {
        LogD(tag: TAG, 'Player prepared successfully');
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _errorMessage = null;
          });

          // 自动开始播放
          _player!.start();
        }
      }).catchError((error) {
        LogE(tag: TAG, 'Player initialization error: $error');
        _handlePlayerError(error);
      });
    } catch (e) {
      LogE(tag: TAG, 'Error creating player: $e');
      _handlePlayerError(e);
    }
  }

  void _playerListener() {
    if (_player == null) return;

    final FijkValue value = _player!.value;

    // 监听播放状态变化
    if (value.state == FijkState.started) {
      if (!_isPlaying) {
        setState(() {
          _isPlaying = true;
        });
      }
    } else if (value.state == FijkState.paused) {
      if (_isPlaying) {
        setState(() {
          _isPlaying = false;
        });
      }
    } else if (value.state == FijkState.error) {
      LogE(tag: TAG, 'Player error: ${value.exception}');
      _handlePlayerError(value.exception);
    }
  }

  void _handlePlayerError(dynamic error) {
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _errorMessage =
            'Failed to load any video. Last error: ${error.toString()}';
      });
    }
  }

  void _togglePlayPause() {
    if (_player == null || !_isInitialized) return;

    if (_isPlaying) {
      _player!.pause();
      LogD(tag: TAG, 'Video paused');
    } else {
      _player!.start();
      LogD(tag: TAG, 'Video playing');
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  void dispose() {
    _player?.removeListener(_playerListener);
    _player?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('IjkPlayer',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _buildVideoContent(),
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    if (!_isInitialized) {
      return _buildLoadingWidget();
    }

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // FijkPlayer视频播放器
          FijkView(
            player: _player!,
            width: double.infinity,
            height: double.infinity,
            fit: FijkFit.contain,
            color: Colors.black,
          ),

          // 控制层
          if (_showControls) _buildControlsOverlay(),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black26,
      child: Stack(
        children: [
          // 中央播放/暂停按钮
          Center(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),

          // 底部控制栏
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 播放/暂停按钮
          GestureDetector(
            onTap: _togglePlayPause,
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 24,
            ),
          ),

          const SizedBox(width: 16),

          // 进度条
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const LinearProgressIndicator(
                backgroundColor: Colors.grey,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // 时间显示
          const Text(
            '00:00 / 00:00',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(height: 16),
        Text(
          'Loading M3U8 video with FijkPlayer...',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 64,
        ),
        const SizedBox(height: 16),
        const Text(
          'Failed to load video',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _errorMessage ?? 'Unknown error occurred',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _errorMessage = null;
              _isInitialized = false;
            });
            _initializePlayer();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }
}
