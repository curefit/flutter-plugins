package io.flutter.plugins.videoplayercf;

import android.content.Context;
import android.os.Build;
import android.util.LongSparseArray;
import io.flutter.FlutterInjector;
import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugins.videoplayercf.Messages.*;
import io.flutter.view.TextureRegistry;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.util.Map;
import javax.net.ssl.HttpsURLConnection;

public class VideoPlayerPlugin implements FlutterPlugin, VideoPlayerApi {
  private static final String TAG = "VideoPlayerPlugin";
  private final LongSparseArray<VideoPlayer> videoPlayers = new LongSparseArray<>();
  private FlutterState flutterState;
  private VideoPlayerOptions options = new VideoPlayerOptions();
  private long maxCacheSize = 100 * 1024 * 1024;
  private long maxCacheFileSize = 10 * 1024 * 1024;

  public VideoPlayerPlugin() {}

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
      try {
        HttpsURLConnection.setDefaultSSLSocketFactory(new CustomSSLSocketFactory());
      } catch (KeyManagementException | NoSuchAlgorithmException e) {
        Log.w(TAG, "Failed to enable TLSv1.1 and TLSv1.2.", e);
      }
    }

    final FlutterInjector injector = FlutterInjector.instance();
    this.flutterState = new FlutterState(
            binding.getApplicationContext(),
            binding.getBinaryMessenger(),
            injector.flutterLoader()::getLookupKeyForAsset,
            injector.flutterLoader()::getLookupKeyForAsset,
            binding.getTextureRegistry());
    flutterState.startListening(this, binding.getBinaryMessenger());
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (flutterState == null) {
      Log.wtf(TAG, "Detached from the engine before registering to it.");
    }
    flutterState.stopListening(binding.getBinaryMessenger());
    flutterState = null;
    initialize(new InitializeMessage());
  }

  private void disposeAllPlayers() {
    for (int i = 0; i < videoPlayers.size(); i++) {
      videoPlayers.valueAt(i).dispose();
    }
    videoPlayers.clear();
  }

  public void initialize(InitializeMessage args) {
    disposeAllPlayers();
  }

  public TextureMessage create(CreateMessage arg) {
    TextureRegistry.SurfaceTextureEntry handle = flutterState.textureRegistry.createSurfaceTexture();
    EventChannel eventChannel = new EventChannel(flutterState.binaryMessenger, "flutter.io/videoPlayer/videoEvents" + handle.id());
    Map<String, String> httpHeaders = arg.getHttpHeaders();
    VideoPlayer player = new VideoPlayer(
            flutterState.applicationContext,
            eventChannel,
            handle,
            arg.getUri(),
            arg.getFormatHint(),
            options,
            maxCacheSize,
            maxCacheFileSize,
            arg.getUseCache(),
            httpHeaders);
    videoPlayers.put(handle.id(), player);
    TextureMessage result = new TextureMessage();
    result.setTextureId(handle.id());
    return result;
  }

  public void dispose(TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) {
      player.dispose();
      videoPlayers.remove(arg.getTextureId());
    }
  }

  public void setLooping(LoopingMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) player.setLooping(arg.getIsLooping());
  }

  public void setVolume(VolumeMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) player.setVolume(arg.getVolume());
  }

  public void setPlaybackSpeed(PlaybackSpeedMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) player.setPlaybackSpeed(arg.getSpeed());
  }

  public void play(TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) player.play();
  }

  public PositionMessage position(TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    PositionMessage result = new PositionMessage();
    if (player != null) {
      result.setPosition(player.getPosition());
      player.sendBufferingUpdate();
    }
    return result;
  }

  public void seekTo(PositionMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) player.seekTo(arg.getPosition().intValue());
  }

  public void pause(TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) player.pause();
  }

  @Override
  public void setMixWithOthers(MixWithOthersMessage arg) {
    options.mixWithOthers = arg.getMixWithOthers();
  }

  @Override
  public void setDataSource(DataSourceMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) {
      if (arg.getAsset() != null) {
        String assetLookupKey = (arg.getPackageName() != null)
                ? flutterState.keyForAssetAndPackageName.get(arg.getAsset(), arg.getPackageName())
                : flutterState.keyForAsset.get(arg.getAsset());
        player.setDataSource(flutterState.applicationContext, arg.getKey(), "asset:///" + assetLookupKey, arg.getFormatHint(), arg.getUseCache(), null);
      } else {
        player.setDataSource(flutterState.applicationContext, arg.getKey(), arg.getUri(), arg.getFormatHint(), arg.getUseCache(), null);
      }
    }
  }


  private interface KeyForAssetFn {
    String get(String asset);
  }

  private interface KeyForAssetAndPackageName {
    String get(String asset, String packageName);
  }

  private static final class FlutterState {
    private final Context applicationContext;
    private final BinaryMessenger binaryMessenger;
    private final KeyForAssetFn keyForAsset;
    private final KeyForAssetAndPackageName keyForAssetAndPackageName;
    private final TextureRegistry textureRegistry;

    FlutterState(Context applicationContext, BinaryMessenger messenger, KeyForAssetFn keyForAsset, KeyForAssetAndPackageName keyForAssetAndPackageName, TextureRegistry textureRegistry) {
      this.applicationContext = applicationContext;
      this.binaryMessenger = messenger;
      this.keyForAsset = keyForAsset;
      this.keyForAssetAndPackageName = keyForAssetAndPackageName;
      this.textureRegistry = textureRegistry;
    }

    void startListening(VideoPlayerPlugin methodCallHandler, BinaryMessenger messenger) {
      VideoPlayerApi.setup(messenger, methodCallHandler);
    }

    void stopListening(BinaryMessenger messenger) {
      VideoPlayerApi.setup(messenger, null);
    }
  }
}
