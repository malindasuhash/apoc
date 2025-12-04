# apoc
Architecture as code POC using LikeC4

## Logical architecture
![Logical](images/Logical-view.png)

## Deployment view
![Deployment](images/Deployment-view.png)

## Workflow
- Prerequsites
    - Gemini AI - I think you can use most AI tools for this.

- High level steps
    - Define application model.
    - Define deployment model.
    - Export architecture model as JSON.
    - Use Gemini AI - content generation capability to generate Terrafom script targetting cloud vendor.

- Use can use the following command to export to JSON.
```
 likec4 export json -o simplePayments.json
```

## Lessons learnt so far
- Use metadata to annotate application model.
    - AI is very good detecting these annotations and adjusting the script.

- Provide hints to AI model.
    - I have created governance.json file that include approved cloud regions and services to use.

- Auto generation alone may not work straight out of the box.
    - I included a section called "tips" in governance.json file to help guide the model. So far I have include **ignore_missing_vnet_service_endpoint** property; not totally sure whether its needed.

- AI Model selection
    - As expected, Gemini Chat interface is different to when you are interacting with the model using APIs. 
    - There are number of models available each with their strengths. There are many models optimised for various tasks.
    - I suspect if we use a code generation model, the outcomes will be much better. 
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