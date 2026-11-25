import QtQuick
import QtMultimedia
import QtTest
import "../../shell/backgrounds"

Item {
    width: 160
    height: 90

    VideoWallpaper {
        id: video
        anchors.fill: parent
        playing: true
        shouldDecode: false
    }

    TestCase {
        name: "VideoWallpaper"
        when: windowShown

        function test_first_frame_pauses_then_resumes_and_pauses_again() {
            video.source = "__VIDEO_URL__";
            tryCompare(video, "hasFirstFrame", true, 5000);
            verify(!video.failed, "The test video failed to load");
            tryCompare(video.player, "playbackState", MediaPlayer.PausedState, 2000);
            const firstPosition = video.player.position;
            verify(firstPosition > 0, "Wallpaper paused before its first frame was decoded");
            wait(250);
            compare(video.player.position, firstPosition, "Paused wallpaper kept advancing");
            video.shouldDecode = true;
            tryCompare(video.player, "playbackState", MediaPlayer.PlayingState, 2000);
            tryVerify(() => video.player.position > firstPosition + 100, 2000);
            video.shouldDecode = false;
            tryCompare(video.player, "playbackState", MediaPlayer.PausedState, 2000);
            const stoppedPosition = video.player.position;
            wait(250);
            compare(video.player.position, stoppedPosition, "Wallpaper continued after decode was disabled");
            video.source = "";
        }
    }
}
