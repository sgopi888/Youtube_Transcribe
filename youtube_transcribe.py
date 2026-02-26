from youtube_transcript_api import YouTubeTranscriptApi

video_id = "gAaCqj6j5sQ"
# https://youtu.be/zyNWbPBkq6E?si=4abD1W7dW63dXl4S
video_id = "zyNWbPBkq6E"
ytt_api = YouTubeTranscriptApi()
result = ytt_api.fetch(video_id)

result = " ".join(snippet.text for snippet in result.snippets)
print(result)