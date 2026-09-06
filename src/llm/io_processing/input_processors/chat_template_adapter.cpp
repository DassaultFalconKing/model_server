//*****************************************************************************
// Copyright 2026 Intel Corporation
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

#include "chat_template_adapter.hpp"

#include <chrono>
#include <fstream>
#include <string>
#include <variant>

#include "../../../logging.hpp"

namespace ovms {
namespace chat_template_adapter {

void funcArgsToObjectHistory(ov::genai::ChatHistory& chatHistory) {
    for (size_t msgIdx = 0; msgIdx < chatHistory.size(); ++msgIdx) {
        auto message = chatHistory[msgIdx];
        if (!message.contains("tool_calls")) {
            continue;
        }
        auto toolCalls = message["tool_calls"];
        if (!toolCalls.is_array()) {
            continue;
        }
        for (size_t i = 0; i < toolCalls.size(); ++i) {
            auto toolCall = toolCalls[i];
            if (!toolCall.is_object() || !toolCall.contains("function")) {
                continue;
            }
            auto function = toolCall["function"];
            if (!function.is_object() || !function.contains("arguments")) {
                continue;
            }
            auto args = function["arguments"];
            if (!args.is_string()) {
                continue;
            }
            std::string argsStr = args.get_string();
            // Parse and replace string arguments with the parsed JSON object
            try {
                function["arguments"] = ov::genai::JsonContainer::from_json_string(argsStr);
            } catch (...) {
                // If parsing fails, leave as-is
                SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Failed to parse function arguments as JSON: {}", argsStr);
                continue;
            }
        }
    }
}

void toolResponseJsonContentToObjectHistory(ov::genai::ChatHistory& chatHistory) {
    for (size_t msgIdx = 0; msgIdx < chatHistory.size(); ++msgIdx) {
        auto message = chatHistory[msgIdx];
        if (!message.contains("role") || !message["role"].is_string() || message["role"].get_string() != "tool") {
            continue;
        }
        if (!message.contains("content") || !message["content"].is_string()) {
            continue;
        }

        const std::string content = message["content"].get_string();
        try {
            auto parsed = ov::genai::JsonContainer::from_json_string(content);
            if (!parsed.is_object()) {
                continue;
            }
            message["content"] = parsed;
        } catch (...) {
            SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Tool response content is not a JSON object; keeping string content");
        }
    }
}

void injectReasoningIntoMissnamedSection(ov::genai::ChatHistory& chatHistory, const std::string& templateReasoningFieldName) {
    for (size_t msgIdx = 0; msgIdx < chatHistory.size(); ++msgIdx) {
        auto message = chatHistory[msgIdx];
        if (!message.contains("reasoning_content") || !message["reasoning_content"].is_string()) {
            continue;
        }

        message[templateReasoningFieldName.c_str()] = message["reasoning_content"].get_string();
    }
}

void applyToHistory(const ChatTemplateCaps& caps, ov::genai::ChatHistory& chatHistory) {
    SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Applying chat template adaptations: {}", caps.toString());
    if (caps.requiresObjectArguments) {
        funcArgsToObjectHistory(chatHistory);
    }
    if (caps.parseToolResponseJsonContent) {
        toolResponseJsonContentToObjectHistory(chatHistory);
    }
    // #region agent log
    {
        std::string argsType = "absent";
        std::string contentType = "absent";
        try {
            auto messages = chatHistory.get_messages();
            if (messages.is_array()) {
                for (size_t i = 0; i < messages.size(); ++i) {
                    auto msg = messages[i];
                    if (msg.is_object() && msg.contains("tool_calls") && msg["tool_calls"].is_array() && msg["tool_calls"].size() > 0) {
                        auto tc0 = msg["tool_calls"][0];
                        if (tc0.is_object() && tc0.contains("function") && tc0["function"].is_object() && tc0["function"].contains("arguments")) {
                            auto args = tc0["function"]["arguments"];
                            argsType = args.is_string() ? "string" : args.is_object() ? "object" : "other";
                        }
                    }
                    if (msg.is_object() && msg.contains("role") && msg["role"].is_string() && msg["role"].get_string() == "tool" && msg.contains("content")) {
                        auto c = msg["content"];
                        contentType = c.is_string() ? "string" : c.is_object() ? "object" : c.is_array() ? "array" : "other";
                    }
                }
            }
        } catch (...) {
            argsType = "exception";
        }
        std::ofstream dbg("C:\\git\\model_server-gemma4-clean\\debug-afec93.log", std::ios::app);
        if (dbg) {
            const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch())
                                .count();
            dbg << "{\"sessionId\":\"afec93\",\"hypothesisId\":\"C\",\"location\":\"chat_template_adapter.cpp:applyToHistory\",\"message\":\"post-adapter argument/content types\",\"data\":{\"requiresObjectArguments\":"
                << (caps.requiresObjectArguments ? "true" : "false")
                << ",\"parseToolResponseJsonContent\":" << (caps.parseToolResponseJsonContent ? "true" : "false")
                << ",\"arguments_type\":\"" << argsType << "\",\"tool_content_type\":\"" << contentType
                << "\"},\"timestamp\":" << ms << ",\"runId\":\"post-fix\"}\n";
        }
    }
    // #endregion
    if (!caps.missnamedReasoningField.empty()) {
        injectReasoningIntoMissnamedSection(chatHistory, caps.missnamedReasoningField);
    }
}

}  // namespace chat_template_adapter

ChatTemplateAdapter::ChatTemplateAdapter(const ChatTemplateCaps& caps) :
    caps(caps) {}

absl::Status ChatTemplateAdapter::process(InputRequest& req) {
    if (!std::holds_alternative<ov::genai::ChatHistory>(req.input)) {
        return absl::OkStatus();
    }
    auto& chatHistory = std::get<ov::genai::ChatHistory>(req.input);
    chat_template_adapter::applyToHistory(caps, chatHistory);
    return absl::OkStatus();
}

}  // namespace ovms
