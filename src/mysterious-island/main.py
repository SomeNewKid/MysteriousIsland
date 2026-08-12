# Copyright (c) Microsoft. All rights reserved.

import os

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

AGENT_CODE_VERSION = "2026-08-12.3"


def main():
    vector_store_id = os.environ["MYSTERIOUS_ISLAND_VECTOR_STORE_ID"]
    print(
        "Mysterious Island agent starting "
        f"version={AGENT_CODE_VERSION} "
        f"model={os.environ['AZURE_AI_MODEL_DEPLOYMENT_NAME']} "
        f"vector_store_id={vector_store_id}",
        flush=True,
    )

    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=DefaultAzureCredential(),
    )
    file_search_tool = FoundryChatClient.get_file_search_tool(
        vector_store_ids=[vector_store_id],
    )

    agent = Agent(
        client=client,
        instructions=(
            "You answer questions about Jules Verne's The Mysterious Island. "
            "For every question about the story, characters, events, chapters, "
            "places, or wording of the novel, use only file search against the "
            "uploaded book text and private reading notes. "
            "The private reading notes may contain experiment-specific facts that "
            "are not in the novel or in your general knowledge. "
            "For questions about secret phrases, verification details, reader "
            "preferences, or private project notes, answer from the private reading "
            "notes. "
            "Do not answer from general model knowledge. "
            "If file search does not provide enough evidence, "
            "say that the uploaded knowledge does not contain enough information."
        ),
        tools=[file_search_tool],
        # History will be managed by the hosting infrastructure, thus there
        # is no need to store history by the service. Learn more at:
        # https://developers.openai.com/api/reference/resources/responses/methods/create
        default_options={
            "store": False,
            "tool_choice": "required",
        },
    )

    server = ResponsesHostServer(agent)
    server.run()


if __name__ == "__main__":
    main()
