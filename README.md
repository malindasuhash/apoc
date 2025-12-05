# Architecture to a Working solution
The goal of this project is to deploy an architecture model defined using LikeC4 to multiple cloud environments as a concrete deployment artifact.

## Logical architecture
![Logical](images/Logical-view.png)

## Deployment view
![Deployment](images/Deployment-view.png)

## Workflow
- Prerequsites
    - LikeC4 installed and ready to use.
    - Gemini AI - I think you can use most AI tools for this.

- High level steps
    - Define application model.
    - Define deployment model.
    - Export architecture model as JSON.
        - It seems that AI models prefer "structured" data (i.e. JSON) than understanding a Domain Specific Language (DSL).
    - Use Gemini AI - content generation capability to generate the Terrafom script targetting a cloud vendor.
    - *There is a subsequent step to deploy the actual program code which I believe require a Docker manifest.*

- Outcome of the above high level steps is the infrasturcture that is ready to deploy application code.

- Once the application and deployement model is defined, then use can use the following command to export it to JSON.
```
 likec4 export json -o simplePayments.json
```

- Once the architecture is exported as a JSON file, then the model can be invoked. The C# solution that invoke Gemini model can be found in "terraform-poc" folder.

- Bulild the project and before you run, have the following environmental variables created.
  - GEMINI_API_KEY - Gemini API key, you need to sign up to get one. There is a free trial available.
  - archJson - Location of simplePayments.json file(e.g. C:\VS\aac\apoc\simplePayments.json).
  - govJson - Governance file (e.g C:\VS\aac\apoc\governance.json).
  - terraform_file - Location and file name where the terraform file should be created (e.g. C:\VS\aac\apoc\main.tf)


## Lessons learnt so far
- Use metadata to annotate application model.
    - AI is very good detecting these annotations and adjusting output script.

- Provide additional hints to the AI model.
    - I have created governance.json file that include approved cloud regions and services to use.

- Auto generation alone may not work straight out of the box.
    - I included a section called "tips" in governance.json file to help guide the generation process. So far I have include **ignore_missing_vnet_service_endpoint** property; not totally sure whether its needed.

- AI Model selection
    - As expected, Gemini Chat interface is different to when you are interacting with the model using APIs. 
    - There are number of models available to interact with but each has strengths. 
    - I suspect if we use a code generation model like GitHub Copilot, then the outcomes will be better. 
    - You can see example list of models that Google offer. There are lots, I mean a lot more!
    - The **supportedGenerationMethods** appears to indicate what features are available. For us its **generateContent** is what we need.
```
    {
  "models": [
    {
      "name": "models/gemini-2.5-pro",
      "version": "2.5",
      "displayName": "Gemini 2.5 Pro",
      "description": "Stable release (June 17th, 2025) of Gemini 2.5 Pro",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/imagen-4.0-generate-001",
      "version": "001",
      "displayName": "Imagen 4",
      "description": "Vertex served Imagen 4.0 model",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predict"
      ]
    },
    {
      "name": "models/veo-2.0-generate-001",
      "version": "2.0",
      "displayName": "Veo 2",
      "description": "Vertex served Veo 2 model. Access to this model requires billing to be enabled on the associated Google Cloud Platform account. Please visit https://console.cloud.google.com/billing to enable it.",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
  ],
  "nextPageToken": "Ch9tb2RlbHMvdmVvLTMuMS1nZW5lcmF0ZS1wcmV2aWV3"
}
```
- Areas to look at are:
    - How to make script generation as predictable as possible?
    - How does updates to existing Terraform script work?
    - Can I retain the same ID? 