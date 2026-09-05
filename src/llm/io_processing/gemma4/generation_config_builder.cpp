//*****************************************************************************
// Copyright 2025 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//*****************************************************************************

#include "generation_config_builder.hpp"
#include <memory>
#include <utility>

namespace ovms {
bool Gemma4GenerationConfigBuilder::isHardToolChoice(const std::string& toolChoice) {
    return toolChoice == "required" ||
        (!toolChoice.empty() && toolChoice != "auto" && toolChoice != "none");
}

std::vector<ov::genai::StructuredOutputConfig::Tag> Gemma4GenerationConfigBuilder::buildToolTags(const OpenAIRequest& request) {
    std::vector<ov::genai::StructuredOutputConfig::Tag> tags;
    tags.reserve(request.toolNameSchemaMap.size());
    for (const auto& [toolName, toolSchemaWrapper] : request.toolNameSchemaMap) {
        ov::genai::StructuredOutputConfig::Tag tag;
        tag.begin = "<|tool_call>call:" + toolName;
        tag.content = ov::genai::StructuredOutputConfig::JSONSchema(toolSchemaWrapper.stringRepr);
        tag.end = "<tool_call|>";
        tags.push_back(std::move(tag));
    }
    return tags;
}

void Gemma4GenerationConfigBuilder::parseConfigFromRequest(const OpenAIRequest& request) {
    BaseGenerationConfigBuilder::parseConfigFromRequest(request);

    if (request.toolNameSchemaMap.empty() || request.toolChoice == "none") {
        return;
    }

    const bool hardToolChoice = isHardToolChoice(request.toolChoice);
    if (!hardToolChoice && !enableToolGuidedGeneration) {
        return;
    }

    auto toolTags = buildToolTags(request);
    if (toolTags.empty()) {
        return;
    }

    if (hardToolChoice) {
        // A TriggeredTags grammar still permits prose before Gemma decides to emit
        // <|tool_call>. Hard choice must constrain from token zero instead.
        auto requiredTags = std::make_shared<ov::genai::StructuredOutputConfig::TagsWithSeparator>();
        requiredTags->tags = std::move(toolTags);
        requiredTags->separator = "";
        requiredTags->at_least_one = true;
        requiredTags->stop_after_first = false;
        ov::genai::StructuredOutputConfig::StructuralTag structuralTag = requiredTags;
        setStructuralTagsConfig(structuralTag);
        return;
    }

    auto triggeredTags = std::make_shared<ov::genai::StructuredOutputConfig::TriggeredTags>();
    triggeredTags->triggers.push_back("<|tool_call>");
    triggeredTags->tags = std::move(toolTags);
    triggeredTags->at_least_one = false;
    triggeredTags->stop_after_first = false;
    ov::genai::StructuredOutputConfig::StructuralTag structuralTag = triggeredTags;
    setStructuralTagsConfig(structuralTag);
}
}  // namespace ovms
