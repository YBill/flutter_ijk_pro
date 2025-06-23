import 'package:fijkplayer/fijkplayer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ijk_pro/log_utils.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with TickerProviderStateMixin {
  static const String TAG = 'TestVideoPage';

  // String get videoUrl => "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8";
  String get videoUrl =>
      "https://overseas-resource-storage.s3.amazonaws.com/explore/test/20250603170705_9e1750c0-1550-423d-b471-53f00ac7297b/v0/prog.m3u8";
  // String get videoUrl => "https://overseas-resource-storage.s3.amazonaws.com/explore/test/20250603170705_9e1750c0-1550-423d-b471-53f00ac7297b/master.m3u8";

  FijkPlayer? _player;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  String? _errorMessage;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isDragging = false;

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
      _player!.setOption(FijkOption.formatCategory, "user_agent", "Flutter FijkPlayer");

      // 针对 HLS 流的特殊设置
      if (videoUrl.contains('.m3u8')) {
        LogD(tag: TAG, 'HLS 流检测到，使用手动循环播放');
        // HLS 流不使用 setLoop，因为可能导致 seek 错误
        // 为 HLS 流添加特殊选项
        _player!.setOption(FijkOption.formatCategory, "live_start_index", -1);
        _player!.setOption(FijkOption.formatCategory, "allowed_media_types", "video+audio");
      } else {
        LogD(tag: TAG, '普通视频文件，使用 setLoop 循环播放');
        // 只对普通视频文件使用 setLoop
        _player!.setLoop(0);
      }

      // 监听播放器状态
      _player!.addListener(_playerListener);

      // 监听播放进度
      _player!.onCurrentPosUpdate.listen((Duration position) {
        if (mounted && !_isDragging) {
          // 只有在有实际进度时才记录日志，避免日志过多
          if (position.inSeconds > 0) {
            // LogD(tag: TAG, '播放进度更新: ${position.inSeconds}秒');
          }
          setState(() {
            _currentPosition = position;
          });
        }
      });

      // 设置数据源并准备播放
      _player!.setDataSource(videoUrl, autoPlay: false).then((_) {
        LogD(tag: TAG, 'Data source set successfully');
        return _player!.prepareAsync();
      }).then((_) {
        LogD(tag: TAG, 'Player prepared successfully, 开始初始化UI状态');
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _isBuffering = true; // 播放器准备好但视频还未渲染，显示缓冲状态
            _errorMessage = null;
          });
          LogD(tag: TAG, '准备调用start()开始播放');
          // 自动开始播放
          _player!.start().then((_) {
            LogD(tag: TAG, 'start()调用成功');
          }).catchError((error) {
            LogE(tag: TAG, 'start()调用失败: $error');
          });
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

    // 详细的状态日志
    LogD(tag: TAG, '播放器状态变化: ${value.state}');
    LogD(tag: TAG, '当前播放状态: isPlaying=$_isPlaying, isBuffering=$_isBuffering, isInitialized=$_isInitialized');
    LogD(tag: TAG, '播放器缓冲状态: ${_player!.isBuffering}');
    LogD(tag: TAG, '视频渲染状态: ${value.videoRenderStart}');
    LogD(tag: TAG, '音频渲染状态: ${value.audioRenderStart}');

    bool shouldUpdateState = false;
    bool newIsPlaying = _isPlaying;
    bool newIsBuffering = _isBuffering;

    // 监听视频渲染开始 - 这是真正可以看到视频的时刻
    if (value.videoRenderStart) {
      LogD(tag: TAG, '视频渲染开始，停止缓冲显示');
      newIsBuffering = false;
      shouldUpdateState = true;
    }
    // 如果播放器已初始化但视频还未渲染，强制显示缓冲
    else if (_isInitialized && !value.videoRenderStart) {
      LogD(tag: TAG, '播放器已初始化但视频未渲染，强制显示缓冲状态');
      newIsBuffering = true;
      shouldUpdateState = true;
    }

    // 监听播放状态变化
    if (value.state == FijkState.started) {
      LogD(tag: TAG, '视频开始播放');
      newIsPlaying = true;
      // 只有当视频渲染开始时才停止缓冲
      if (value.videoRenderStart) {
        newIsBuffering = false;
      }
      shouldUpdateState = true;
    } else if (value.state == FijkState.paused) {
      LogD(tag: TAG, '视频暂停');
      newIsPlaying = false;
      shouldUpdateState = true;
    } else if (value.state == FijkState.prepared) {
      LogD(tag: TAG, '播放器准备完成，等待播放');
      newIsBuffering = true;
      shouldUpdateState = true;
    } else if (value.state == FijkState.asyncPreparing) {
      LogD(tag: TAG, '播放器正在异步准备');
      newIsBuffering = true;
      shouldUpdateState = true;
    } else if (value.state == FijkState.idle) {
      LogD(tag: TAG, '播放器空闲状态');
    } else if (value.state == FijkState.initialized) {
      LogD(tag: TAG, '播放器初始化完成');
    } else if (value.state == FijkState.completed) {
      LogD(tag: TAG, '播放完成');
      // 根据视频类型选择循环策略
      if (videoUrl.contains('.m3u8')) {
        LogD(tag: TAG, 'HLS 流播放完成，使用手动循环播放');
        // HLS 流使用手动循环，避免 seek 错误
        _player?.seekTo(0).then((_) {
          _player?.start();
          LogD(tag: TAG, 'HLS 流循环播放已开始');
        }).catchError((error) {
          LogE(tag: TAG, 'HLS 流循环播放失败: $error');
        });
      } else {
        LogD(tag: TAG, '普通视频播放完成 - setLoop(0) 会自动循环');
      }
    } else if (value.state == FijkState.stopped) {
      LogD(tag: TAG, '播放停止');
    } else if (value.state == FijkState.error) {
      LogE(tag: TAG, 'Player error: ${value.exception}');
      _handlePlayerError(value.exception);
    }

    // 统一更新状态
    if (shouldUpdateState && mounted) {
      if (newIsPlaying != _isPlaying || newIsBuffering != _isBuffering) {
        LogD(tag: TAG, '更新状态: isPlaying=$newIsPlaying, isBuffering=$newIsBuffering');
        setState(() {
          _isPlaying = newIsPlaying;
          _isBuffering = newIsBuffering;
        });
      }
    }

    // 更新总时长
    if (mounted && value.duration != _totalDuration) {
      LogD(tag: TAG, '视频总时长: ${value.duration}');
      setState(() {
        _totalDuration = value.duration;
      });
    }
  }

  void _handlePlayerError(dynamic error) {
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _errorMessage = 'Failed to load any video. Last error: ${error.toString()}';
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
        title: Text('IjkPlayer', style: const TextStyle(color: Colors.white, fontSize: 16)),
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
          // ijkPlayer视频播放器
          FijkView(
            player: _player!,
            width: double.infinity,
            height: double.infinity,
            fit: FijkFit.contain,
            color: Colors.black,
            panelBuilder: (player, data, context, viewSize, texturePos) => Container(), // 隐藏默认控制器
          ),

          // 缓冲指示器 - 只要在缓冲状态就显示
          if (_isBuffering) _buildBufferingIndicator(),

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
          // 中央播放/暂停按钮 - 缓冲时不显示，避免重叠
          if (!_isBuffering)
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
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbColor: Colors.red,
                activeTrackColor: Colors.red,
                inactiveTrackColor: Colors.grey,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: _totalDuration.inMilliseconds > 0
                    ? _currentPosition.inMilliseconds.toDouble().clamp(0.0, _totalDuration.inMilliseconds.toDouble())
                    : 0.0,
                max: _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0,
                onChanged: (value) {
                  setState(() {
                    _currentPosition = Duration(milliseconds: value.toInt());
                  });
                },
                onChangeStart: (_) => _isDragging = true,
                onChangeEnd: (value) {
                  _isDragging = false;
                  _player?.seekTo(value.toInt());
                },
              ),
            ),
          ),

          const SizedBox(width: 16),

          // 时间显示
          Text(
            '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Loading动画
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: Colors.red,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                const Text(
                  '正在加载视频...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'M3U8 直播流',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                // 添加一些点动画效果
                _buildLoadingDots(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferingIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Colors.red,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            const Text(
              '缓冲中...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDot(0),
        const SizedBox(width: 4),
        _buildDot(1),
        const SizedBox(width: 4),
        _buildDot(2),
      ],
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween(begin: 0.3, end: 1.0),
      builder: (context, value, child) {
        return AnimatedOpacity(
          duration: Duration(milliseconds: 400 + (index * 200)),
          opacity: value,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
      onEnd: () {
        // 循环动画效果可以通过定时器实现，但这里简化处理
      },
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
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
