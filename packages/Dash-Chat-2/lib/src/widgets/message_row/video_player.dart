part of dash_chat_2;

/// @nodoc
class VideoPlayer extends StatefulWidget {
  const VideoPlayer({
    required this.url,
    this.aspectRatio = 1,
  });

  /// Link of the video
  final String url;

  /// The Aspect Ratio of the Video. Important to get the correct size of the video
  final double aspectRatio;

  @override
  _VideoPlayerState createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {

  @override
  void initState() {
    super.initState();

  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? Stack(
            alignment: _controller.value.isPlaying
                ? AlignmentDirectional.bottomStart
                : AlignmentDirectional.center,
            children: <Widget>[
              IconButton(
                iconSize: _controller.value.isPlaying ? 24 : 60,
                onPressed: () {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                },
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  // size: 60,
                ),
              ),
            ],
          )
        : Container();
  }
}
