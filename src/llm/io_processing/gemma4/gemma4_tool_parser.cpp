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
#include "gemma4_tool_parser.hpp"
#include "../utils.hpp"
#include "../../../logging.hpp"
#include "../../../stringutils.hpp"
#include "rapidjson/error/en.h"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <string_view>
#include <utility>

namespace ovms {
namespace {

constexpr std::string_view GEMMA4_STRING_DELIM = "<|\"|>";

std::string quoteJsonString(const std::string& value) {
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    writer.String(value.c_str(), static_cast<rapidjson::SizeType>(value.size()));
    return buffer.GetString();
}

std::string trimCopy(std::string value) {
    trim(value);
    return value;
}

bool isJsonNumber(const std::string& value) {
    if (value.empty()) {
        return false;
    }
    char* end = nullptr;
    std::strtod(value.c_str(), &end);
    return end != value.c_str() && end == value.c_str() + value.size();
}

// Gemma4 does not serialize function arguments as JSON. Strings use <|"|>
// delimiters, object keys are normally bare, and values may recurse into
// arrays/objects. Convert that dialect to JSON with one structural parser
// instead of ad-hoc comma searches that lose nested values.
class Gemma4ValueReader {
public:
    explicit Gemma4ValueReader(const std::string& input) : input(input) {}

    std::string parse() {
        skipWhitespace();
        return parseValue();
    }

private:
    bool startsWith(std::string_view token) const {
        return pos + token.size() <= input.size() &&
            std::string_view(input).substr(pos, token.size()) == token;
    }

    void skipWhitespace() {
        while (pos < input.size() && std::isspace(static_cast<unsigned char>(input[pos]))) {
            pos++;
        }
    }

    std::string parseSpecialStringRaw() {
        pos += GEMMA4_STRING_DELIM.size();
        const size_t end = input.find(GEMMA4_STRING_DELIM, pos);
        if (end == std::string::npos) {
            std::string value = input.substr(pos);
            pos = input.size();
            return value;
        }
        std::string value = input.substr(pos, end - pos);
        pos = end + GEMMA4_STRING_DELIM.size();
        return value;
    }

    std::string parseQuotedStringRaw() {
        const char quote = input[pos++];
        std::string value;
        while (pos < input.size()) {
            const char current = input[pos++];
            if (current == quote) {
                break;
            }
            if (current == '\\' && pos < input.size()) {
                const char escaped = input[pos++];
                switch (escaped) {
                case 'n':
                    value.push_back('\n');
                    break;
                case 'r':
                    value.push_back('\r');
                    break;
                case 't':
                    value.push_back('\t');
                    break;
                default:
                    value.push_back(escaped);
                    break;
                }
                continue;
            }
            value.push_back(current);
        }
        return value;
    }

    std::string parseKeyRaw() {
        skipWhitespace();
        if (startsWith(GEMMA4_STRING_DELIM)) {
            return parseSpecialStringRaw();
        }
        if (pos < input.size() && (input[pos] == '"' || input[pos] == '\'')) {
            return parseQuotedStringRaw();
        }

        const size_t start = pos;
        while (pos < input.size() && input[pos] != ':' && input[pos] != '=' && input[pos] != ',' && input[pos] != '}') {
            pos++;
        }
        return trimCopy(input.substr(start, pos - start));
    }

    std::string parseBareValue() {
        const size_t start = pos;
        while (pos < input.size() && input[pos] != ',' && input[pos] != '}' && input[pos] != ']') {
            pos++;
        }
        std::string value = trimCopy(input.substr(start, pos - start));
        std::string lower = value;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });

        if (lower == "true" || lower == "false" || lower == "null") {
            return lower;
        }
        if (isJsonNumber(value)) {
            return value;
        }
        return quoteJsonString(value);
    }

    std::string parseObject() {
        pos++;  // {
        std::string output = "{";
        bool first = true;

        while (pos < input.size()) {
            skipWhitespace();
            if (pos < input.size() && input[pos] == '}') {
                pos++;
                break;
            }
            if (pos < input.size() && input[pos] == ',') {
                pos++;
                skipWhitespace();
            }
            if (pos >= input.size() || input[pos] == '}') {
                if (pos < input.size()) {
                    pos++;
                }
                break;
            }

            const size_t keyStart = pos;
            const std::string key = parseKeyRaw();
            skipWhitespace();
            if (pos >= input.size() || (input[pos] != ':' && input[pos] != '=')) {
                // Malformed tail. Do not invent a key/value pair and, critically,
                // do not loop forever on the same byte.
                if (pos == keyStart) {
                    pos++;
                }
                break;
            }
            pos++;  // : or =
            skipWhitespace();

            const std::string value = parseValue();
            if (!first) {
                output.push_back(',');
            }
            output += quoteJsonString(key);
            output.push_back(':');
            output += value;
            first = false;

            skipWhitespace();
            if (pos < input.size() && input[pos] == ',') {
                pos++;
                continue;
            }
            if (pos < input.size() && input[pos] == '}') {
                pos++;
                break;
            }
        }

        output.push_back('}');
        return output;
    }

    std::string parseArray() {
        pos++;  // [
        std::string output = "[";
        bool first = true;

        while (pos < input.size()) {
            skipWhitespace();
            if (pos < input.size() && input[pos] == ']') {
                pos++;
                break;
            }
            if (pos < input.size() && input[pos] == ',') {
                pos++;
                skipWhitespace();
            }
            if (pos >= input.size() || input[pos] == ']') {
                if (pos < input.size()) {
                    pos++;
                }
                break;
            }

            const size_t valueStart = pos;
            const std::string value = parseValue();
            if (pos == valueStart) {
                pos++;
                continue;
            }
            if (!first) {
                output.push_back(',');
            }
            output += value;
            first = false;

            skipWhitespace();
            if (pos < input.size() && input[pos] == ',') {
                pos++;
                continue;
            }
            if (pos < input.size() && input[pos] == ']') {
                pos++;
                break;
            }
        }

        output.push_back(']');
        return output;
    }

    std::string parseValue() {
        skipWhitespace();
        if (pos >= input.size()) {
            return "\"\"";
        }
        if (startsWith(GEMMA4_STRING_DELIM)) {
            return quoteJsonString(parseSpecialStringRaw());
        }
        if (input[pos] == '{') {
            return parseObject();
        }
        if (input[pos] == '[') {
            return parseArray();
        }
        if (input[pos] == '"' || input[pos] == '\'') {
            return quoteJsonString(parseQuotedStringRaw());
        }
        return parseBareValue();
    }

    const std::string& input;
    size_t pos{0};
};

}  // namespace

const std::string Gemma4ToolParser::TOOL_CALL_START_TAG = "<|tool_call>";
const std::string Gemma4ToolParser::TOOL_CALL_END_TAG = "<tool_call|>";
const std::string Gemma4ToolParser::TOOL_CALL_NAME_PREFIX = "call:";

const std::string Gemma4ToolParser::TOOL_ARGS_START_INDICATOR = "{";
const std::string Gemma4ToolParser::TOOL_ARGS_END_INDICATOR = "}";
const std::string Gemma4ToolParser::TOOL_ARGS_STRING_INDICATOR = "<|\"|>";
const std::string Gemma4ToolParser::TOOL_ARGS_SEPARATOR_STR = ",";

const std::string Gemma4ToolParser::TURN_END_TAG = "<turn|>";
const std::string Gemma4ToolParser::TOOL_RESPONSE_START_TAG = "<|tool_response>";

const int64_t Gemma4ToolParser::botTokenId = 48;  // <|tool_call>
const int64_t Gemma4ToolParser::eotTokenId = 49;  // <tool_call|>

const int64_t Gemma4ToolParser::reasoningTokenId = 100;     // <|channel>
const int64_t Gemma4ToolParser::reasoningEndTokenId = 101;  // <channel|>

std::string Gemma4ToolParser::parseArrayParameter(const std::string& argumentStr) {
    return Gemma4ValueReader(argumentStr).parse();
}

std::string Gemma4ToolParser::parseObjectParameter(const std::string& argumentStr) {
    return Gemma4ValueReader(argumentStr).parse();
}

std::string Gemma4ToolParser::normalizeArgStr(const std::string& arg) {
    if (arg.empty()) {
        return arg;
    }

    std::string normalized = arg;
    trim(normalized);
    std::string lower = normalized;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

    if (lower == "true" || lower == "false" || lower == "null") {
        return lower;
    }

    if ((!normalized.empty() && (normalized.front() == '{' || normalized.front() == '[')) ||
        normalized.rfind(TOOL_ARGS_STRING_INDICATOR, 0) == 0) {
        normalized = Gemma4ValueReader(normalized).parse();
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Converted Gemma4 structured argument to JSON: {}", normalized);
    }

    rapidjson::Document tempDoc;
    rapidjson::Value finalValue;
    tempDoc.Parse(normalized.c_str());
    if (tempDoc.HasParseError()) {
        auto errorCode = tempDoc.GetParseError();
        auto errorMessage = rapidjson::GetParseError_En(errorCode);
        size_t errorOffset = tempDoc.GetErrorOffset();
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Failed to parse argument string as JSON. Argument string: {}, Error: {} Offset: {}", normalized, errorMessage, errorOffset);

        if (normalized.front() == '\"' && normalized.back() == '\"') {
            normalized = normalized.substr(1, normalized.size() - 2);
        }
        finalValue.SetString(normalized.c_str(), static_cast<rapidjson::SizeType>(normalized.size()), tempDoc.GetAllocator());
    } else {
        finalValue.CopyFrom(tempDoc, tempDoc.GetAllocator());
    }

    {
        rapidjson::StringBuffer buffer;
        rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
        finalValue.Accept(writer);
        normalized = buffer.GetString();
    }

    return normalized;
}

void Gemma4ToolParser::writeArgumentToWriter(const std::string& arg, rapidjson::Writer<rapidjson::StringBuffer>& writer) {
    std::string normalized = normalizeArgStr(arg);

    rapidjson::Document doc;
    doc.Parse(normalized.c_str());

    rapidjson::Value& argumentDoc = doc;
    writeArgumentOfAnyType(argumentDoc, writer);
}

std::pair<std::string, std::string> Gemma4ToolParser::parseSingleArgument(const std::string& argumentStr) {
    std::pair<std::string, std::string> argument;

    size_t colonPos = argumentStr.find(':');
    if (colonPos != std::string::npos) {
        argument.first = argumentStr.substr(0, colonPos);
        std::string value = argumentStr.substr(colonPos + 1);
        argument.second = value;
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed argument - name: {}, value: {}", argument.first, argument.second);
    } else {
        argument.first = argumentStr;
        argument.second = "";
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Argument string: {} does not contain ':', setting name as entire string and value as empty", argumentStr);
    }
    return argument;
}

std::string Gemma4ToolParser::maskStringValues(const std::string& text) {
    std::string masked = text;
    size_t pos = 0;
    while (true) {
        const size_t openPos = text.find(TOOL_ARGS_STRING_INDICATOR, pos);
        if (openPos == std::string::npos)
            break;
        const size_t valueStart = openPos + TOOL_ARGS_STRING_INDICATOR.size();
        const size_t closePos = text.find(TOOL_ARGS_STRING_INDICATOR, valueStart);
        // Value not closed yet (still streaming): mask through the current buffer end too,
        // otherwise its already-received tail would desync quote/brace tracking; a later
        // call re-masks from scratch once the closing delimiter has arrived.
        const size_t maskEnd = (closePos == std::string::npos) ? text.size() : closePos;
        for (size_t i = valueStart; i < maskEnd; i++) {
            switch (masked[i]) {
            case '"':
            case '\'':
            case '{':
            case '}':
            case '[':
            case ']':
                masked[i] = '\x01';
                break;
            default:
                break;
            }
        }
        if (closePos == std::string::npos)
            break;
        pos = closePos + TOOL_ARGS_STRING_INDICATOR.size();
    }
    return masked;
}

std::vector<std::pair<std::string, std::string>> Gemma4ToolParser::parseArguments(const std::string& argumentsStr) {
    std::vector<std::string> args;
    std::vector<std::pair<std::string, std::string>> parsedArgs;

    const std::string maskedArgumentsStr = maskStringValues(argumentsStr);
    size_t argPos = 0;
    while (argPos < argumentsStr.length()) {
        size_t commaPos = findInStringRespectingSpecialChars(maskedArgumentsStr, TOOL_ARGS_SEPARATOR_STR, argPos);
        if (commaPos == std::string::npos) {
            auto remainingStr = argumentsStr.substr(argPos);
            args.push_back(remainingStr);
            SPDLOG_LOGGER_TRACE(llm_calculator_logger, "No more commas found, adding remaining argument string: {}", remainingStr);
            break;
        }
        std::string argStr = argumentsStr.substr(argPos, commaPos - argPos);
        args.push_back(argStr);
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed argument string: {}", argStr);
        argPos = commaPos + TOOL_ARGS_SEPARATOR_STR.length();
    }

    for (const std::string& arg : args) {
        parsedArgs.push_back(parseSingleArgument(arg));
    }
    return parsedArgs;
}

bool Gemma4ToolParser::parseInContentState() {
    size_t toolCallStartTagPos = this->streamingContent.find(TOOL_CALL_START_TAG, this->streamingPosition);
    if (toolCallStartTagPos != std::string::npos) {
        if (toolCallStartTagPos > this->streamingPosition) {
            SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Content found before tool call start tag at position: {}", toolCallStartTagPos);
            return true;
        }
        this->streamingPosition = toolCallStartTagPos + TOOL_CALL_START_TAG.length();
        this->currentState = State::ToolCallStarted;
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Detected start of tool call at position: {}", toolCallStartTagPos);
        return false;
    }

    return true;
}

bool Gemma4ToolParser::parseInToolCallState() {
    size_t argsPos = this->streamingContent.find(TOOL_ARGS_START_INDICATOR, this->streamingPosition);
    if (argsPos == std::string::npos) {
        return false;
    }

    size_t toolNameStart = this->streamingContent.find(TOOL_CALL_NAME_PREFIX, this->streamingPosition);
    if (toolNameStart != std::string::npos && toolNameStart < argsPos) {
        toolNameStart += TOOL_CALL_NAME_PREFIX.length();
    } else {
        toolNameStart = this->streamingPosition;
    }

    std::string toolName = this->streamingContent.substr(toolNameStart, argsPos - toolNameStart);
    trim(toolName);
    this->toolCall = ToolCall{generateRandomId(), toolName, ""};
    SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed tool name: {}", toolName);
    this->streamingPosition = argsPos + TOOL_ARGS_START_INDICATOR.length();
    this->currentState = State::ToolCallParameters;
    this->toolCallIndex++;
    return true;
}

bool Gemma4ToolParser::parseToolCallParametersState() {
    if (this->streamingContent.back() == TOOL_ARGS_END_INDICATOR.back()) {
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Tool arguments end indicator found at the end of streaming content, attempting to parse arguments: {}", this->streamingContent.substr(this->streamingPosition));
    }
    const std::string maskedStreamingContent = maskStringValues(this->streamingContent);
    size_t pos = findInStringRespectingSpecialChars(maskedStreamingContent, TOOL_ARGS_END_INDICATOR, this->streamingPosition);
    if (pos == std::string::npos) {
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Tool arguments end indicator not found in streaming content starting from position: {}", this->streamingPosition);
        return false;
    }
    std::string argumentsStr = this->streamingContent.substr(this->streamingPosition, pos - this->streamingPosition);
    SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed arguments string: {}", argumentsStr);
    std::vector<std::pair<std::string, std::string>> arguments = parseArguments(argumentsStr);

    rapidjson::Document argsDoc(rapidjson::kObjectType);
    rapidjson::StringBuffer sb;
    rapidjson::Writer<rapidjson::StringBuffer> argsWriter(sb);
    argsWriter.StartObject();

    for (const std::pair<std::string, std::string>& argument : arguments) {
        argsWriter.Key(argument.first.c_str());
        writeArgumentToWriter(argument.second, argsWriter);
    }

    argsWriter.EndObject();
    this->toolCall.arguments = sb.GetString();
    this->currentState = State::ToolCallEnded;
    this->streamingPosition = pos + TOOL_ARGS_END_INDICATOR.length();

    return true;
}

bool Gemma4ToolParser::parseInToolCallEndedState() {
    size_t nextToolCallPos = this->streamingContent.find(TOOL_CALL_NAME_PREFIX, this->streamingPosition);
    const size_t canonicalEndPos = this->streamingContent.find(TOOL_CALL_END_TAG, this->streamingPosition);
    const size_t turnEndPos = this->streamingContent.find(TURN_END_TAG, this->streamingPosition);
    size_t toolCallEndTagPos = canonicalEndPos;
    size_t toolCallEndTagLength = TOOL_CALL_END_TAG.length();
    if (turnEndPos != std::string::npos && (toolCallEndTagPos == std::string::npos || turnEndPos < toolCallEndTagPos)) {
        toolCallEndTagPos = turnEndPos;
        toolCallEndTagLength = TURN_END_TAG.length();
    }

    SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Current state: ToolCallEnded. Streaming content from current position: {}", this->streamingContent.substr(this->streamingPosition));
    if (nextToolCallPos != std::string::npos && (toolCallEndTagPos == std::string::npos || nextToolCallPos < toolCallEndTagPos)) {
        this->streamingPosition = nextToolCallPos;
        this->currentState = State::ToolCallStarted;
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Detected next tool call at position: {}", nextToolCallPos);
        return true;
    }
    if (toolCallEndTagPos != std::string::npos) {
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Detected end of tool call at position: {}", toolCallEndTagPos);
        this->streamingPosition = toolCallEndTagPos + toolCallEndTagLength;
        this->currentState = State::AfterToolCall;
        return true;
    }
    // The call arguments may already be complete while the end marker is still in flight.
    // Keep the parser in ToolCallEnded and wait instead of doing arithmetic on npos and
    // prematurely treating subsequent bytes as ordinary content.
    return false;
}

bool Gemma4ToolParser::parseNewContent() {
    switch (this->currentState) {
    case State::Content: {
        return parseInContentState();
    }
    case State::ToolCallStarted: {
        return parseInToolCallState();
    }
    case State::ToolCallParameters: {
        return parseToolCallParametersState();
    }
    case State::ToolCallEnded: {
        return parseInToolCallEndedState();
    }
    case State::AfterToolCall:
        break;
    }
    return false;
}

std::optional<rapidjson::Document> Gemma4ToolParser::wrapDeltaContent(const std::string& content) {
    if (content.empty() || content == "") {
        return std::nullopt;
    }
    rapidjson::Document doc(rapidjson::kObjectType);
    rapidjson::Value deltaObj(rapidjson::kObjectType);
    deltaObj.AddMember("content", rapidjson::Value(content.c_str(), doc.GetAllocator()), doc.GetAllocator());
    doc.AddMember("delta", deltaObj, doc.GetAllocator());
    return doc;
}

rapidjson::Document Gemma4ToolParser::wrapDeltaArgs(const std::string& argsStr, int toolCallIndex) {
    rapidjson::Document doc(rapidjson::kObjectType);
    doc.AddMember("arguments", rapidjson::Value(argsStr.c_str(), doc.GetAllocator()), doc.GetAllocator());

    return BaseOutputParser::wrapDelta(doc, toolCallIndex);
}

std::optional<rapidjson::Document> Gemma4ToolParser::parseChunk(const std::string& chunk, const std::vector<int64_t>& /*tokens*/, ov::genai::GenerationFinishReason finishReason) {
    if (!chunk.empty()) {
        this->streamingContent += chunk;
    }

    // If we enter a new parseChunk() already in ToolCallParameters, the function-name delta
    // was necessarily emitted by the previous call. If we reach ToolCallParameters for the
    // first time inside this invocation and finishReason is already terminal, no later SSE
    // callback is guaranteed, so the final delta must carry both name and arguments.
    const bool nameAlreadyEmittedAtEntry = this->currentState == State::ToolCallParameters;
    auto wrapNameAndArgs = [this]() {
        auto delta = BaseOutputParser::wrapFirstDelta(this->toolCall.name, this->toolCallIndex);
        auto& function = delta["delta"]["tool_calls"][0]["function"];
        rapidjson::Value argsValue(this->toolCall.arguments.c_str(), delta.GetAllocator());
        function.AddMember("arguments", argsValue, delta.GetAllocator());
        return delta;
    };

    // A backend chunk is not guaranteed to align with Gemma4 parser states. In particular,
    // `<|tool_call>call:name{...}<tool_call|>` can arrive as one decoded chunk. Drain
    // non-emitting state transitions until we can emit one meaningful OpenAI delta or until
    // no state/position progress is possible. We still emit at most one delta per call.
    while (true) {
        const State previousState = this->currentState;
        const size_t previousPosition = this->streamingPosition;
        const bool parsed = parseNewContent();

        if (this->currentState == State::ToolCallParameters && previousState != State::ToolCallParameters) {
            if (finishReason == ov::genai::GenerationFinishReason::NONE) {
                return BaseOutputParser::wrapFirstDelta(this->toolCall.name, toolCallIndex);
            }
            // Terminal chunk: keep draining so we can return an identifiable complete call
            // rather than consuming the finish signal with a name-only delta.
        }
        if (this->currentState == State::ToolCallEnded && previousState != State::ToolCallEnded) {
            auto delta = nameAlreadyEmittedAtEntry ? wrapDeltaArgs(this->toolCall.arguments, toolCallIndex) : wrapNameAndArgs();
            this->toolCall = ToolCall{};
            return delta;
        }
        if (parsed && this->currentState == State::Content) {
            size_t contentEnd = this->streamingContent.find(TOOL_CALL_START_TAG, this->streamingPosition);
            std::string content;
            if (contentEnd != std::string::npos) {
                content = this->streamingContent.substr(this->streamingPosition, contentEnd - this->streamingPosition);
            } else {
                content = this->streamingContent.substr(this->streamingPosition);
            }
            this->streamingPosition += content.size();

            // Structural/stop markers must never reach the client, on any chunk, not just the final flush.
            for (const std::string& tagToErase : {TURN_END_TAG, TOOL_RESPONSE_START_TAG}) {
                size_t tagPos = content.find(tagToErase);
                while (tagPos != std::string::npos) {
                    content.erase(tagPos, tagToErase.length());
                    tagPos = content.find(tagToErase, tagPos);
                }
            }

            return wrapDeltaContent(content);
        }
        if (this->currentState == State::AfterToolCall) {
            this->currentState = State::Content;
        }

        const bool advanced = this->currentState != previousState || this->streamingPosition != previousPosition;
        if (!advanced) {
            break;
        }
    }

    if (finishReason != ov::genai::GenerationFinishReason::NONE) {
        // Recover a call only when the function name and argument-start brace were already
        // generated and only structural closure is missing. Insert synthetic closure before
        // any already-generated turn/tool marker so marker bytes never become argument data.
        if (this->currentState == State::ToolCallParameters && this->toolCall.arguments.empty() && !this->toolCall.name.empty()) {
            size_t closurePos = this->streamingContent.size();
            for (const std::string& marker : {TOOL_CALL_END_TAG, TURN_END_TAG, TOOL_RESPONSE_START_TAG}) {
                const size_t markerPos = this->streamingContent.find(marker, this->streamingPosition);
                if (markerPos != std::string::npos) {
                    closurePos = std::min(closurePos, markerPos);
                }
            }

            size_t delimiterCount = 0;
            size_t delimiterPos = this->streamingPosition;
            while ((delimiterPos = this->streamingContent.find(TOOL_ARGS_STRING_INDICATOR, delimiterPos)) != std::string::npos && delimiterPos < closurePos) {
                delimiterCount++;
                delimiterPos += TOOL_ARGS_STRING_INDICATOR.size();
            }
            if (delimiterCount % 2 != 0) {
                this->streamingContent.insert(closurePos, TOOL_ARGS_STRING_INDICATOR);
                closurePos += TOOL_ARGS_STRING_INDICATOR.size();
            }

            const std::string maskedStreamingContent = maskStringValues(this->streamingContent);
            const size_t closingBracePos = findInStringRespectingSpecialChars(maskedStreamingContent, TOOL_ARGS_END_INDICATOR, this->streamingPosition);
            if (closingBracePos == std::string::npos || closingBracePos >= closurePos) {
                this->streamingContent.insert(closurePos, TOOL_ARGS_END_INDICATOR);
            }

            if (parseToolCallParametersState() && this->currentState == State::ToolCallEnded && !this->toolCall.arguments.empty()) {
                auto delta = nameAlreadyEmittedAtEntry ? wrapDeltaArgs(this->toolCall.arguments, toolCallIndex) : wrapNameAndArgs();
                this->toolCall = ToolCall{};
                return delta;
            }
        }

        if ((this->currentState == State::ToolCallParameters || this->currentState == State::ToolCallEnded) && !this->toolCall.arguments.empty()) {
            auto delta = nameAlreadyEmittedAtEntry ? wrapDeltaArgs(this->toolCall.arguments, toolCallIndex) : wrapNameAndArgs();
            this->toolCall = ToolCall{};
            return delta;
        }

        if (this->currentState == State::Content && this->streamingPosition < this->streamingContent.size()) {
            auto content = this->streamingContent.substr(this->streamingPosition);
            this->streamingPosition += content.size();

            for (const std::string& tagToErase : getSpecialTagsToErase()) {
                size_t tagPos = content.find(tagToErase);
                while (tagPos != std::string::npos) {
                    content.erase(tagPos, tagToErase.length());
                    tagPos = content.find(tagToErase, tagPos);
                }
            }

            return wrapDeltaContent(content);
        }
    }

    return std::nullopt;
}

bool Gemma4ToolParser::parseSingleToolCall(const std::string& toolStr, ToolCall& toolCall) {
    size_t argsPos = toolStr.find(TOOL_ARGS_START_INDICATOR);
    if (argsPos != std::string::npos) {
        std::string toolNameWithPrefix = toolStr.substr(0, argsPos);
        if (toolNameWithPrefix.find(TOOL_CALL_NAME_PREFIX) != 0) {
            SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Tool name does not start with expected prefix '{}'. Tool string: {}", TOOL_CALL_NAME_PREFIX, toolStr);
            return false;
        }
        std::string toolName = toolNameWithPrefix.substr(TOOL_CALL_NAME_PREFIX.length());
        trim(toolName);
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed tool name: {}", toolName);

        int argsStrLen = toolStr.length() - argsPos - TOOL_ARGS_START_INDICATOR.length() - TOOL_ARGS_END_INDICATOR.length();
        std::string argsStr = toolStr.substr(argsPos + TOOL_ARGS_START_INDICATOR.length(), argsStrLen);
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed args string: {}", argsStr);
        std::vector<std::pair<std::string, std::string>> arguments = parseArguments(argsStr);

        toolCall.name = toolName;
        rapidjson::Document argsDoc(rapidjson::kObjectType);
        rapidjson::StringBuffer sb;
        rapidjson::Writer<rapidjson::StringBuffer> argsWriter(sb);
        argsWriter.StartObject();
        for (const std::pair<std::string, std::string>& argument : arguments) {
            argsWriter.Key(argument.first.c_str());
            writeArgumentToWriter(argument.second, argsWriter);
        }
        argsWriter.EndObject();
        toolCall.arguments = sb.GetString();
        toolCall.id = generateRandomId();
        return true;
    }
    return false;
}

void Gemma4ToolParser::parse(ParsedOutput& parsedOutput, const std::vector<int64_t>& generatedTokens) {
    std::vector<std::string> tools;
    std::vector<std::pair<size_t, size_t>> toolCallPositions;
    size_t pos = 0;

    const auto vocab = tokenizer.get_vocab();
    const auto turnEndTokenIt = vocab.find(TURN_END_TAG);
    const std::optional<int64_t> turnEndTokenId = turnEndTokenIt == vocab.end() ? std::nullopt : std::optional<int64_t>(turnEndTokenIt->second);

    while (pos != std::string::npos) {
        size_t start = std::string::npos;
        size_t end = std::string::npos;

        auto it = std::find(generatedTokens.begin() + pos, generatedTokens.end(), botTokenId);
        if (it != generatedTokens.end()) {
            start = std::distance(generatedTokens.begin(), it);
        } else {
            break;
        }

        auto canonicalEndIt = std::find(generatedTokens.begin() + start, generatedTokens.end(), eotTokenId);
        auto selectedEndIt = canonicalEndIt;
        if (turnEndTokenId.has_value()) {
            auto turnEndIt = std::find(generatedTokens.begin() + start, generatedTokens.end(), turnEndTokenId.value());
            if (turnEndIt != generatedTokens.end() && (selectedEndIt == generatedTokens.end() || turnEndIt < selectedEndIt)) {
                selectedEndIt = turnEndIt;
            }
        }
        if (selectedEndIt != generatedTokens.end()) {
            end = std::distance(generatedTokens.begin(), selectedEndIt);
        } else {
            break;
        }

        std::string toolCallStr = tokenizer.decode(std::vector<int64_t>(generatedTokens.begin() + start + 1, generatedTokens.begin() + end + 1), ov::AnyMap{ov::genai::skip_special_tokens(false)});
        SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed tool list string: {}", toolCallStr);

        while (!toolCallStr.empty()) {
            size_t nextToolPos = toolCallStr.find(TOOL_CALL_NAME_PREFIX, TOOL_CALL_NAME_PREFIX.length());
            size_t toolEndPos;
            if (nextToolPos == std::string::npos) {
                toolEndPos = toolCallStr.rfind(TOOL_ARGS_END_INDICATOR);
            } else {
                toolEndPos = nextToolPos - 1;
            }
            std::string singleTool;
            if (toolEndPos != std::string::npos) {
                singleTool = toolCallStr.substr(0, toolEndPos + TOOL_ARGS_END_INDICATOR.length());
                if (toolEndPos + TOOL_ARGS_END_INDICATOR.length() < toolCallStr.length()) {
                    toolCallStr = toolCallStr.substr(toolEndPos + TOOL_ARGS_END_INDICATOR.length());
                } else {
                    toolCallStr.clear();
                }
                SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed single tool string {}", singleTool);
            } else {
                SPDLOG_LOGGER_TRACE(llm_calculator_logger, "No more tool strings found in the decoded string: {}", toolCallStr);
                break;
            }

            if (!singleTool.empty()) {
                tools.push_back(singleTool);
            }
        }

        pos = end;
        toolCallPositions.emplace_back(start, end);
    }

    for (const std::string& tool : tools) {
        ToolCall toolCall;
        auto wasToolCallParsed = parseSingleToolCall(tool, toolCall);
        if (wasToolCallParsed) {
            SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Parsed tool call - name: {}, args: {}", toolCall.name, toolCall.arguments);
            parsedOutput.toolCalls.push_back(toolCall);
        } else {
            SPDLOG_LOGGER_TRACE(llm_calculator_logger, "Failed to parse tool call from string: {}", tool);
        }
    }
    std::vector<int64_t> contentWithoutToolCalls = generatedTokens;
    for (auto it = toolCallPositions.rbegin(); it != toolCallPositions.rend(); ++it) {
        contentWithoutToolCalls.erase(contentWithoutToolCalls.begin() + it->first, contentWithoutToolCalls.begin() + it->second + 1);
    }

    auto reasoningEnd = std::find(contentWithoutToolCalls.begin(), contentWithoutToolCalls.end(), reasoningEndTokenId);
    if (reasoningEnd != contentWithoutToolCalls.end()) {
        contentWithoutToolCalls.erase(contentWithoutToolCalls.begin(), reasoningEnd + 1);
    }
    parsedOutput.content = tokenizer.decode(contentWithoutToolCalls, ov::AnyMap{ov::genai::skip_special_tokens(true)});
}
}  // namespace ovms
