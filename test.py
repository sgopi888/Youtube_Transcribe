from openai_client import summarize_transcript

sample_transcript = """
In this video, we're going to talk about the latest updates in AI. OpenAI has just released gpt-5-nano, which is a highly efficient model for summarizing long transcripts. 
It uses a new responses API which is different from the traditional chat completions. 
We'll show you how to use it with simple Python scripts. 
First, you need to set up your API key. Then you can use the responses.create method. 
The output contains the summary directly in the output_text field. 
This is great for developers who want a more structured way to interact with the models.
"""

try:
    print("\nTesting summarize_transcript:")
    summary = summarize_transcript(sample_transcript)
    print("Summary:")
    print(summary)
except Exception as e:
    print(f"Error during summarization: {e}")
