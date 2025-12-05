using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

public class BuildTargetScript
{
    // Configuration
    private static readonly string ApiKey = GetVariable("GEMINI_API_KEY");
    // Using the REST Endpoint for Gemini 1.5 Pro
    private static readonly string ApiUrl = $"https://generativelanguage.googleapis.com/v1beta/models/nano-banana-pro-preview:generateContent?key={ApiKey}";

    public static async Task Build(string[] args)
    {
       // await ListAvailableModels();
        
        if (string.IsNullOrEmpty(ApiKey))
        {
            Console.WriteLine("Error: Please set the GEMINI_API_KEY environment variable.");
            return;
        }

        Console.WriteLine("1. Reading input files...");
        string archJson, govJson;

        try
        {
            archJson = await File.ReadAllTextAsync(GetVariable("archJson"));
            govJson = await File.ReadAllTextAsync(GetVariable("govJson"));
        }
        catch (FileNotFoundException ex)
        {
            Console.WriteLine($"Error: Could not find input file. {ex.Message}");
            return;
        }

        // 2. Construct the Prompt
        string prompt = $@"
        You are an expert DevOps engineer and Terraform architect.
        
        Your goal is to write a production-ready Azure Terraform script (`main.tf`) based on two input files provided below.
        
        ### INPUT 1: Architecture Definition (LikeC4 JSON)
        {archJson}
        
        ### INPUT 2: Governance Policy (JSON)
        {govJson}

        ### REQUIREMENTS:
        1. Merge the logic: Use the topology from Input 1, but enforce the SKUs/Regions from Input 2.
        2. Conflict Resolution: If Input 1 is generic (e.g., 'Database'), Input 2 is the authority (e.g., 'Azure SQL Standard').
        3. Output strictly valid HCL (Terraform) code.
        4. Do not include markdown formatting (like ```hcl), just the raw code.
        ";

        // 3. Prepare the JSON Payload
        var requestBody = new
        {
            contents = new[]
            {
                new { parts = new[] { new { text = prompt } } }
            },
            generationConfig = new
            {
                temperature = 0.2   // Reduce randomness              
            }
        };

        string jsonPayload = JsonSerializer.Serialize(requestBody);
        using var client = new HttpClient();
        var content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

        Console.WriteLine("2. Calling Gemini API...");
        var response = await client.PostAsync(ApiUrl, content);

        if (!response.IsSuccessStatusCode)
        {
            string errorBody = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"API Request Failed: {response.StatusCode}");
            Console.WriteLine(errorBody);
            return;
        }

        // 4. Parse Response
        string responseBody = await response.Content.ReadAsStringAsync();
        using JsonDocument doc = JsonDocument.Parse(responseBody);
        
        // Navigate the JSON: candidates[0] -> content -> parts[0] -> text
        try 
        {
            string terraformCode = doc.RootElement
                .GetProperty("candidates")[0]
                .GetProperty("content")
                .GetProperty("parts")[0]
                .GetProperty("text")
                .GetString();

            // 5. Clean and Save
            terraformCode = CleanMarkdown(terraformCode);
            
            string terraform_file = GetVariable("terraform_file");
            await File.WriteAllTextAsync(terraform_file, terraformCode);
            Console.WriteLine($"SUCCESS: {terraform_file} has been generated.");
        }
        catch (Exception ex)
        {
            Console.WriteLine("Error parsing API response. The model might have returned an unexpected format.");
            Console.WriteLine(ex.Message);
        }
    }

    private static string CleanMarkdown(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        
        text = text.Trim();
        
        // Remove ```hcl or ```terraform at the start
        if (text.StartsWith("```"))
        {
            int firstNewline = text.IndexOf('\n');
            if (firstNewline > -1)
            {
                text = text.Substring(firstNewline + 1);
            }
            
            // Remove trailing ```
            if (text.EndsWith("```"))
            {
                text = text.Substring(0, text.Length - 3);
            }
        }
        
        return text.Trim();
    }

    private static async Task ListAvailableModels()
    {
        string listUrl = $"https://generativelanguage.googleapis.com/v1beta/models?key={ApiKey}";
        using var client = new HttpClient();
        var response = await client.GetAsync(listUrl);
        string json = await response.Content.ReadAsStringAsync();
        Console.WriteLine(json);
    }

    private static string GetVariable(string key)
    {
        return Environment.GetEnvironmentVariable(key);
    }
}