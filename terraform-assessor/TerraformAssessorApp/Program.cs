using System.Text.Json;
using System.Text.Json.Serialization;
using Google.Cloud.AIPlatform.V1;
using Value = Google.Protobuf.WellKnownTypes.Value;


namespace TerraformAssessorApp
{
    public class AssessmentResult
    {
        [JsonPropertyName("file_path")]
        public string? FilePath { get; set; }

        [JsonPropertyName("success_rating")]
        public string? SuccessRating { get; set; }

        [JsonPropertyName("observations")]
        public List<string>? Observations { get; set; }
    }

    public class Program
    {
        public static async Task Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.WriteLine("Usage: TerraformAssessorApp <path_to_terraform_file>");
                return;
            }

            string filePath = args[0];
            if (!File.Exists(filePath))
            {
                Console.WriteLine($"Error: File not found at '{filePath}'");
                return;
            }

            string fileContent = await File.ReadAllTextAsync(filePath);
            
            try
            {
                var assessment = await GetAssessmentFromApiAsync(fileContent);
                assessment.FilePath = filePath;

                var options = new JsonSerializerOptions { WriteIndented = true };
                string jsonResponse = JsonSerializer.Serialize(assessment, options);

                string outputFileName = "assessment_report.json";
                await File.WriteAllTextAsync(outputFileName, jsonResponse);

                Console.WriteLine($"Assessment report written to '{outputFileName}'");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred: {ex.Message}");
            }
        }

        private static async Task<AssessmentResult> GetAssessmentFromApiAsync(string fileContent)
        {
            const string location = "us-central1";
            const string publisher = "google";
            const string model = "gemini-1.5-flash-001";
            
            string? projectId = Environment.GetEnvironmentVariable("GOOGLE_PROJECT_ID");
            if (string.IsNullOrEmpty(projectId))
            {
                throw new InvalidOperationException("Please set the GOOGLE_PROJECT_ID environment variable.");
            }

            var predictionServiceClient = new PredictionServiceClientBuilder
            {
                Endpoint = $"{location}-aiplatform.googleapis.com"
            }.Build();

            var generateContentRequest = new GenerateContentRequest
            {
                Model = $"projects/{projectId}/locations/{location}/publishers/{publisher}/models/{model}",
                Contents =
                {
                    new Content
                    {
                        Role = "USER",
                        Parts =
                        {
                            new Part
                            {
                                Text = @"Analyze the following Terraform HCL file. Evaluate its adherence to security best practices, naming conventions, and overall code quality.

                                Return your assessment ONLY as a JSON object with the following structure:
                                {
                                  ""success_rating"": ""[High|Medium|Low]"",
                                  ""observations"": [
                                    ""Observation 1"",
                                    ""Observation 2""
                                  ]
                                }

                                Do not include any text or markdown formatting before or after the JSON object.

                                Terraform file content:
                                ```hcl
                                " + fileContent + @"
                                ```"
                            }
                        }
                    }
                }
            };

            GenerateContentResponse response = await predictionServiceClient.GenerateContentAsync(generateContentRequest);

            string responseJson = response.Candidates.First().Content.Parts.First().Text;
            
            // Clean the response to ensure it's valid JSON
            responseJson = responseJson.Trim().Trim('`');
            if (responseJson.StartsWith("json"))
            {
                responseJson = responseJson.Substring(4).Trim();
            }

            var assessmentResult = JsonSerializer.Deserialize<AssessmentResult>(responseJson);
            
            if (assessmentResult == null)
            {
                throw new InvalidOperationException("Failed to deserialize the assessment response from the API.");
            }

            return assessmentResult;
        }
    }
}
