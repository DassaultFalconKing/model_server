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
#include <gmock/gmock.h>
#include <gtest/gtest.h>
#include <rapidjson/document.h>

#include <fstream>
#include <string>

#include <openvino/genai/tokenizer.hpp>

#include "../../llm/servable.hpp"
#include "../../llm/servable_initializer.hpp"
#include "src/test/test_utils.hpp"
#include "src/test/light_test_utils.hpp"
#include "src/test/test_with_temp_dir.hpp"

using namespace ovms;

class MaxModelLengthTest : public TestWithTempDir {
protected:
    std::string configFilePath;
    rapidjson::Document doc;
    ov::genai::Tokenizer dummyTokenizer;

    void SetUp() {
        TestWithTempDir::SetUp();
        configFilePath = directoryPath + "/config.json";
    }
};

TEST_F(MaxModelLengthTest, maxModelLength_MaxPositionEmbeddings_VALID) {
    std::string modelConfigContent = R"({"max_position_embeddings" : 5})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_MaxPositionEmbeddings_INVALID) {
    std::string modelConfigContent = R"({"max_position_embeddings" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_nPositions_VALID) {
    std::string modelConfigContent = R"({"n_positions" : 5})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_nPositions_INVALID) {
    std::string modelConfigContent = R"({"n_positions" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_seqLen_VALID) {
    std::string modelConfigContent = R"({"seq_len" : 5})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_seqLen_INVALID) {
    std::string modelConfigContent = R"({"seq_len" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_seqLength_VALID) {
    std::string modelConfigContent = R"({"seq_length" : 5})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_seqLength_INVALID) {
    std::string modelConfigContent = R"({"seq_length" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_nCtx_VALID) {
    std::string modelConfigContent = R"({"n_ctx" : 5})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_nCtx_INVALID) {
    std::string modelConfigContent = R"({"n_ctx" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_slidingWindow_VALID) {
    std::string modelConfigContent = R"({"sliding_window" : 5})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_slidingWindow_INVALID) {
    std::string modelConfigContent = R"({"sliding_window" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_emptyConfig) {
    std::string modelConfigContent = R"({})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

TEST_F(MaxModelLengthTest, maxModelLength_parsingOrder) {
    std::string modelConfigContent = R"({"max_position_embeddings" : 5, "seq_length" : 6, "n_positions" : 7, "sliding_window" : 8, "seq_len" : 9, "n_ctx" : 10})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_textConfig_VALID) {
    // Composite VLM/omni configs (e.g. Qwen3.5-Omni) nest the field under "text_config".
    std::string modelConfigContent = R"({"model_type" : "qwen3_5", "text_config" : {"max_position_embeddings" : 262144}})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 262144);
}

TEST_F(MaxModelLengthTest, maxModelLength_topLevelTakesPriorityOverTextConfig) {
    std::string modelConfigContent = R"({"max_position_embeddings" : 5, "text_config" : {"max_position_embeddings" : 262144}})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    ASSERT_TRUE(maxModelLength.has_value());
    EXPECT_EQ(maxModelLength.value(), 5);
}

TEST_F(MaxModelLengthTest, maxModelLength_textConfig_notAnObject) {
    std::string modelConfigContent = R"({"text_config" : "INVALID"})";
    createConfigFileWithContent(modelConfigContent, configFilePath);
    auto maxModelLength = parseMaxModelLength(directoryPath);
    EXPECT_FALSE(maxModelLength.has_value());
}

namespace {
rapidjson::Document makeSessionRequest(const std::optional<uint32_t>& seed = std::nullopt) {
    rapidjson::Document doc;
    doc.SetObject();
    auto& allocator = doc.GetAllocator();
    doc.AddMember("model", rapidjson::Value("gemma4-test", allocator), allocator);
    rapidjson::Value messages(rapidjson::kArrayType);
    rapidjson::Value message(rapidjson::kObjectType);
    message.AddMember("role", rapidjson::Value("user", allocator), allocator);
    message.AddMember("content", rapidjson::Value("hello", allocator), allocator);
    messages.PushBack(message, allocator);
    doc.AddMember("messages", messages, allocator);
    if (seed.has_value())
        doc.AddMember("seed", seed.value(), allocator);
    return doc;
}
}  // namespace

class SessionStateStoreTest : public TestWithTempDir {};

TEST_F(SessionStateStoreTest, FirstTurnWithoutSeedGeneratesAndPersistsNonZeroSeed) {
    SessionStateStore store(directoryPath, 4, 1024 * 1024, 64 * 1024);
    auto doc = makeSessionRequest();
    const std::string raw = R"({"model":"gemma4-test","messages":[{"role":"user","content":"hello"}]})";

    auto turn = store.beginTurn("session-a", raw, doc);
    ASSERT_TRUE(turn.ok()) << turn.status();
    EXPECT_GT(turn->seed, 0u);
    ASSERT_TRUE(doc.HasMember("seed"));
    EXPECT_EQ(doc["seed"].GetUint(), turn->seed);
    EXPECT_TRUE(std::ifstream(directoryPath + "/session-a/manifest.json").good());
    EXPECT_TRUE(std::ifstream(directoryPath + "/session-a/turns/000000000001/raw-request.json").good());
    EXPECT_TRUE(std::ifstream(directoryPath + "/session-a/turns/000000000001/effective-request.json").good());
}

TEST_F(SessionStateStoreTest, ExplicitFirstSeedBecomesSessionSeed) {
    SessionStateStore store(directoryPath, 4, 1024 * 1024, 64 * 1024);
    auto doc = makeSessionRequest(424242u);
    auto turn = store.beginTurn("session-explicit", R"({"seed":424242})", doc);
    ASSERT_TRUE(turn.ok()) << turn.status();
    EXPECT_EQ(turn->seed, 424242u);
}

TEST_F(SessionStateStoreTest, LaterTurnWithoutSeedReusesPersistedSeed) {
    SessionStateStore store(directoryPath, 4, 1024 * 1024, 64 * 1024);
    auto firstDoc = makeSessionRequest(123456u);
    ASSERT_TRUE(store.beginTurn("session-reuse", R"({"seed":123456})", firstDoc).ok());

    auto secondDoc = makeSessionRequest();
    auto second = store.beginTurn("session-reuse", R"({"messages":[]})", secondDoc);
    ASSERT_TRUE(second.ok()) << second.status();
    EXPECT_EQ(second->turnIndex, 2u);
    EXPECT_EQ(second->seed, 123456u);
    EXPECT_EQ(secondDoc["seed"].GetUint(), 123456u);
}

TEST_F(SessionStateStoreTest, DifferentExplicitSeedReturnsConflict) {
    SessionStateStore store(directoryPath, 4, 1024 * 1024, 64 * 1024);
    auto firstDoc = makeSessionRequest(7u);
    ASSERT_TRUE(store.beginTurn("session-conflict", R"({"seed":7})", firstDoc).ok());

    auto conflicting = makeSessionRequest(8u);
    auto result = store.beginTurn("session-conflict", R"({"seed":8})", conflicting);
    EXPECT_FALSE(result.ok());
    EXPECT_THAT(std::string(result.status().message()), testing::HasSubstr("session seed conflict"));
}

TEST_F(SessionStateStoreTest, NewStoreInstanceReloadsPersistedSeed) {
    {
        SessionStateStore first(directoryPath, 1, 1024 * 1024, 64 * 1024);
        auto doc = makeSessionRequest(31337u);
        ASSERT_TRUE(first.beginTurn("session-reload", R"({"seed":31337})", doc).ok());
    }

    SessionStateStore reloaded(directoryPath, 1, 1024 * 1024, 64 * 1024);
    auto doc = makeSessionRequest();
    auto turn = reloaded.beginTurn("session-reload", R"({"messages":[]})", doc);
    ASSERT_TRUE(turn.ok()) << turn.status();
    EXPECT_EQ(turn->seed, 31337u);
    EXPECT_EQ(turn->turnIndex, 2u);
}

TEST_F(SessionStateStoreTest, RejectsUnsafeSessionId) {
    SessionStateStore store(directoryPath, 4, 1024 * 1024, 64 * 1024);
    auto doc = makeSessionRequest();
    auto result = store.beginTurn("../escape", R"({"messages":[]})", doc);
    EXPECT_FALSE(result.ok());
}

TEST_F(SessionStateStoreTest, RefusesRequestPastConfiguredRequestLimit) {
    SessionStateStore store(directoryPath, 4, 1024 * 1024, 16);
    auto doc = makeSessionRequest();
    auto result = store.beginTurn("session-large", std::string(128, 'x'), doc);
    EXPECT_FALSE(result.ok());
}
