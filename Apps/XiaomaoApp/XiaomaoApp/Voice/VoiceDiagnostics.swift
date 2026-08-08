import CryptoKit
import Foundation

struct VoiceLatencySample: Equatable, Sendable {
    let networkPingMilliseconds: Int?
    let endpointSilenceMilliseconds: Int
    let commitToTranscriptFinalMilliseconds: Int?
    let transcriptFinalToResponseStartedMilliseconds: Int?
    let responseStartedToFirstAudioMilliseconds: Int?
    let endToFirstAudioMilliseconds: Int?
    let serverCommitForwardMilliseconds: Int?
    let serverCommitToTranscriptFinalMilliseconds: Int?
    let serverTranscriptFinalToResponseStartedMilliseconds: Int?
    let serverResponseStartedToFirstAudioMilliseconds: Int?
}

struct VoiceRecoveryEvent: Equatable, Sendable {
    let name: String
    let at: Date
}

struct VoiceDiagnosticSnapshot: Sendable {
    let appBuildSHA: String
    let appBuildTime: String
    let state: VoiceSessionState
    let webSocketState: VoiceWebSocketState
    let adapterMode: String
    let sessionHash: String
    let lastCloseCode: Int?
    let lastErrorCategory: String
    let lastReasonCategory: String
    let lastTransportErrorDomain: String
    let lastTransportErrorCode: Int?
    let lastDisconnectRecoverable: Bool
    let reconnectAttempt: Int
    let reconnectCount: Int
    let microphonePermission: MicrophonePermissionState
    let audioSessionActive: Bool
    let audioRouteDescription: String
    let lastServerEventType: String
    let lastServerEventAt: Date?
    let inputAudioChunks: Int
    let outputAudioChunks: Int
    let providerErrorCount: Int
    let networkType: NetworkConnectionType
    let vadState: VoiceActivityState
    let vadEnergyBand: String
    let vadNormalizedRMS: Double
    let vadConfiguration: VoiceActivityConfiguration
    let speechStartCount: Int
    let automaticCommitCount: Int
    let rejectedNoiseCount: Int
    let bargeInDetectionCount: Int
    let interruptSentCount: Int
    let interruptSuccessCount: Int
    let ignoredInterruptedAudioChunks: Int
    let webSocketResourceTimeoutSeconds: Int
    let webSocketConnectedDurationMilliseconds: Int?
    let lastDisconnectUptimeMilliseconds: Int?
    let endToFirstAudioMilliseconds: Int?
    let networkPingMilliseconds: Int?
    let pingFailureCount: Int
    let commitToTranscriptFinalMilliseconds: Int?
    let transcriptFinalToResponseStartedMilliseconds: Int?
    let responseStartedToFirstAudioMilliseconds: Int?
    let serverCommitForwardMilliseconds: Int?
    let serverCommitToTranscriptFinalMilliseconds: Int?
    let serverTranscriptFinalToResponseStartedMilliseconds: Int?
    let serverResponseStartedToFirstAudioMilliseconds: Int?
    let latencySamples: [VoiceLatencySample]
    let firstInputChunkSentAt: Date?
    let audioCommitSentAt: Date?
    let transcriptFinalReceivedAt: Date?
    let responseStartedAt: Date?
    let firstAudioDeltaReceivedAt: Date?
    let responseNextSentCount: Int
    let serverPushAudioChunks: Int
    let continuousCaptureActive: Bool
    let captureEngineRunning: Bool
    let captureTapInstalled: Bool
    let captureCallbackCount: Int
    let lastCaptureCallbackAt: Date?
    let captureRestartCount: Int
    let audioEngineStartCount: Int
    let audioEngineStopCount: Int
    let playbackStartCount: Int
    let audioInterruptionCount: Int
    let engineConfigurationChangeCount: Int
    let uploadConnectionGeneration: Int
    let uploadCaptureGeneration: Int
    let uploadNextChunkIndex: Int
    let uploadNextClientSequence: Int
    let uploadQueueDepth: Int
    let uploadQueueHighWater: Int
    let uploadSentAudioChunks: Int
    let uploadSentControlCommands: Int
    let uploadDroppedStaleGenerationChunks: Int
    let uploadRejectedAfterCloseCommands: Int
    let uploadStaleGenerationSendFailureCount: Int
    let uploadActiveGenerationSendFailureCount: Int
    let uploadInputBackpressureCount: Int
    let uploadMaxActiveDrainTasks: Int
    let uploadLastFiveSentChunkIndices: [Int]
    let uploadLastSendFailureCategory: String
    let uploadGenerationStartedAt: Date?
    let uploadCaptureToProcessingLagMilliseconds: Int
    let uploadMaxCaptureToProcessingLagMilliseconds: Int
    let uploadLastCapturePacketMilliseconds: Int
    let uploadMaxCapturePacketMilliseconds: Int
    let uploadOutboundBatchBytes: Int
    let uploadOutboundQueueDepth: Int
    let uploadOutboundQueueHighWater: Int
    let uploadOutboundBackpressureCount: Int
    let uploadOutboundOldestQueuedAgeMilliseconds: Int
    let uploadLastTransportSendMilliseconds: Int
    let uploadMaxTransportSendMilliseconds: Int
    let uploadCaptureToProcessingLagAtCommitMilliseconds: Int
    let uploadCommitQueuedAt: Date?
    let uploadCommitSentAt: Date?
    let uploadCommitQueueToSendMilliseconds: Int
    let recoveryLastDisconnectAt: Date?
    let recoveryLastReconnectStartedAt: Date?
    let recoveryLastTransportConnectedAt: Date?
    let recoveryLastSessionReadyAt: Date?
    let recoveryLastCaptureResumedAt: Date?
    let recoveryLastGapMilliseconds: Int?
    let recoveryTimeline: [VoiceRecoveryEvent]
    let playbackActive: Bool
    let lastSpeechDurationMilliseconds: Int
    let lastEndingSilenceMilliseconds: Int
    let presentationToAudioSessionMilliseconds: Int?
    let presentationToWebSocketMilliseconds: Int?
    let presentationToSessionReadyMilliseconds: Int?
    let presentationToMicrophoneReadyMilliseconds: Int?
    let responseCompletionCount: Int
    let postResponseCaptureRecoveryCount: Int
    let lastResponseCompletionCaptureCallbacks: Int
    let postResponseCaptureCallbackDelta: Int
    let generatedAt: Date

    var latencySummary: String {
        let stages: [(String, Int?)] = [
            ("网络 RTT", networkPingMilliseconds),
            ("ASR / 上行", commitToTranscriptFinalMilliseconds),
            ("模型 / 路由", transcriptFinalToResponseStartedMilliseconds),
            ("TTS / 下行", responseStartedToFirstAudioMilliseconds)
        ]
        let available = stages.compactMap { stage -> (String, Int)? in
            guard let value = stage.1 else { return nil }
            return (stage.0, value)
        }
        let slowest = available.max { $0.1 < $1.1 }
        let recent = Array(latencySamples.suffix(10))
        var lines = [
            "延迟分段（客户端观测）",
            "网络 RTT: \(optional(networkPingMilliseconds)) ms",
            "端点静音等待: \(lastEndingSilenceMilliseconds) ms",
            "采集→处理排队: \(uploadCaptureToProcessingLagMilliseconds) ms（峰值 \(uploadMaxCaptureToProcessingLagMilliseconds) ms）",
            "提交时采集→处理排队: \(uploadCaptureToProcessingLagAtCommitMilliseconds) ms",
            "commit 排队→发送完成: \(uploadCommitQueueToSendMilliseconds) ms",
            "网络发送耗时: \(uploadLastTransportSendMilliseconds) ms（峰值 \(uploadMaxTransportSendMilliseconds) ms）",
            "ASR / 上行: \(optional(commitToTranscriptFinalMilliseconds)) ms",
            "模型 / 路由: \(optional(transcriptFinalToResponseStartedMilliseconds)) ms",
            "TTS / 下行: \(optional(responseStartedToFirstAudioMilliseconds)) ms",
            "commit→首音频: \(optional(endToFirstAudioMilliseconds)) ms",
            "Ping 失败次数: \(pingFailureCount)",
            "当前最长阶段: \(slowest.map { "\($0.0) \($0.1) ms" } ?? "数据不足")",
            "口径: commit→首音频从提交发送开始；提交前的采集排队单列显示"
        ]

        if !recent.isEmpty {
            lines.append("")
            lines.append("最近 \(recent.count) 轮统计（median / p95）")
            lines.append("网络 RTT: \(aggregate(recent, \.networkPingMilliseconds)) ms")
            lines.append("端点静音等待: \(aggregate(recent, \.endpointSilenceMilliseconds)) ms")
            lines.append("ASR / 上行: \(aggregate(recent, \.commitToTranscriptFinalMilliseconds)) ms")
            lines.append("模型 / 路由: \(aggregate(recent, \.transcriptFinalToResponseStartedMilliseconds)) ms")
            lines.append("TTS / 下行: \(aggregate(recent, \.responseStartedToFirstAudioMilliseconds)) ms")
            lines.append("commit→首音频: \(aggregate(recent, \.endToFirstAudioMilliseconds)) ms")
        }

        let serverStages: [(String, Int?)] = [
            ("commit 入队→Provider", serverCommitForwardMilliseconds),
            ("commit→ASR final", serverCommitToTranscriptFinalMilliseconds),
            ("ASR final→response.started", serverTranscriptFinalToResponseStartedMilliseconds),
            ("response.started→首音频", serverResponseStartedToFirstAudioMilliseconds)
        ]
        if serverStages.contains(where: { $0.1 != nil }) {
            lines.append("")
            lines.append("服务端分段（最后一轮）")
            for stage in serverStages {
                lines.append("\(stage.0): \(optional(stage.1)) ms")
            }
        }

        return lines.joined(separator: "\n")
    }

    var text: String {
        let formatter = ISO8601DateFormatter()
        let lastEventTime = lastServerEventAt.map(formatter.string(from:)) ?? "none"
        return [
            "Xiaomao iOS voice diagnostics",
            "app_commit=\(safe(appBuildSHA, fallback: "unknown"))",
            "app_build_time=\(safe(appBuildTime, fallback: "unknown"))",
            "state=\(state.rawValue)",
            "websocket_state=\(webSocketState.rawValue)",
            "adapter_mode=\(safe(adapterMode, fallback: "Empty"))",
            "session_hash=\(sessionHash)",
            "last_close_code=\(lastCloseCode.map(String.init) ?? "none")",
            "last_error_category=\(safe(lastErrorCategory, fallback: "none"))",
            "last_reason_category=\(safe(lastReasonCategory, fallback: "none"))",
            "last_transport_error_domain=\(safe(lastTransportErrorDomain, fallback: "none"))",
            "last_transport_error_code=\(lastTransportErrorCode.map(String.init) ?? "none")",
            "recoverable=\(lastDisconnectRecoverable)",
            "reconnect_attempt=\(reconnectAttempt)",
            "reconnect_count=\(reconnectCount)",
            "route=b",
            "microphone_permission=\(microphonePermission.rawValue)",
            "audio_session_active=\(audioSessionActive)",
            "audio_route=\(safe(audioRouteDescription, fallback: "unknown"))",
            "last_server_event=\(safe(lastServerEventType, fallback: "none"))",
            "last_server_event_time=\(lastEventTime)",
            "input_audio_chunks=\(inputAudioChunks)",
            "output_audio_chunks=\(outputAudioChunks)",
            "provider_error_count=\(providerErrorCount)",
            "network_type=\(networkType.rawValue)",
            "vad_state=\(vadState.rawValue)",
            "vad_energy_band=\(safe(vadEnergyBand, fallback: "unknown"))",
            "vad_rms=\(String(format: "%.4f", vadNormalizedRMS))",
            "vad_pre_roll_ms=\(vadConfiguration.preRollMilliseconds)",
            "vad_min_speech_ms=\(vadConfiguration.minimumSpeechMilliseconds)",
            "vad_barge_min_speech_ms=\(vadConfiguration.bargeInMinimumSpeechMilliseconds)",
            "vad_end_silence_ms=\(vadConfiguration.endSilenceMilliseconds)",
            "vad_max_utterance_ms=\(vadConfiguration.maximumUtteranceMilliseconds)",
            "vad_speech_threshold=\(String(format: "%.4f", vadConfiguration.speechRMSThreshold))",
            "vad_barge_threshold=\(String(format: "%.4f", vadConfiguration.bargeInRMSThreshold))",
            "speech_start_count=\(speechStartCount)",
            "automatic_commit_count=\(automaticCommitCount)",
            "rejected_noise_count=\(rejectedNoiseCount)",
            "barge_in_detection_count=\(bargeInDetectionCount)",
            "interrupt_sent_count=\(interruptSentCount)",
            "interrupt_success_count=\(interruptSuccessCount)",
            "ignored_interrupted_audio_chunks=\(ignoredInterruptedAudioChunks)",
            "websocket_resource_timeout_seconds=\(webSocketResourceTimeoutSeconds)",
            "websocket_connected_duration_ms=\(optional(webSocketConnectedDurationMilliseconds))",
            "last_disconnect_uptime_ms=\(optional(lastDisconnectUptimeMilliseconds))",
            "end_to_first_audio_ms=\(optional(endToFirstAudioMilliseconds))",
            "network_ping_ms=\(optional(networkPingMilliseconds))",
            "ping_failure_count=\(pingFailureCount)",
            "commit_to_transcript_final_ms=\(optional(commitToTranscriptFinalMilliseconds))",
            "transcript_final_to_response_started_ms=\(optional(transcriptFinalToResponseStartedMilliseconds))",
            "response_started_to_first_audio_ms=\(optional(responseStartedToFirstAudioMilliseconds))",
            "server_commit_forward_ms=\(optional(serverCommitForwardMilliseconds))",
            "server_commit_to_transcript_final_ms=\(optional(serverCommitToTranscriptFinalMilliseconds))",
            "server_transcript_final_to_response_started_ms=\(optional(serverTranscriptFinalToResponseStartedMilliseconds))",
            "server_response_started_to_first_audio_ms=\(optional(serverResponseStartedToFirstAudioMilliseconds))",
            "latency_sample_count=\(latencySamples.count)",
            "latency_recent_window=\(min(10, latencySamples.count))",
            "latency_recent_end_to_first_audio_median_ms=\(aggregateValue(latencySamples.suffix(10), \.endToFirstAudioMilliseconds, percentile: 0.50))",
            "latency_recent_end_to_first_audio_p95_ms=\(aggregateValue(latencySamples.suffix(10), \.endToFirstAudioMilliseconds, percentile: 0.95))",
            "first_input_chunk_sent_at=\(date(firstInputChunkSentAt, formatter: formatter))",
            "audio_commit_sent_at=\(date(audioCommitSentAt, formatter: formatter))",
            "transcript_final_received_at=\(date(transcriptFinalReceivedAt, formatter: formatter))",
            "response_started_at=\(date(responseStartedAt, formatter: formatter))",
            "first_audio_delta_received_at=\(date(firstAudioDeltaReceivedAt, formatter: formatter))",
            "response_next_sent_count=\(responseNextSentCount)",
            "server_push_audio_chunks=\(serverPushAudioChunks)",
            "continuous_capture_active=\(continuousCaptureActive)",
            "capture_engine_running=\(captureEngineRunning)",
            "capture_tap_installed=\(captureTapInstalled)",
            "capture_callback_count=\(captureCallbackCount)",
            "last_capture_callback_at=\(date(lastCaptureCallbackAt, formatter: formatter))",
            "last_capture_callback_age_ms=\(captureCallbackAgeMilliseconds())",
            "capture_restart_count=\(captureRestartCount)",
            "audio_engine_start_count=\(audioEngineStartCount)",
            "audio_engine_stop_count=\(audioEngineStopCount)",
            "playback_start_count=\(playbackStartCount)",
            "audio_interruption_count=\(audioInterruptionCount)",
            "engine_configuration_change_count=\(engineConfigurationChangeCount)",
            "upload_connection_generation=\(uploadConnectionGeneration)",
            "upload_capture_generation=\(uploadCaptureGeneration)",
            "upload_next_chunk_index=\(uploadNextChunkIndex)",
            "upload_next_client_sequence=\(uploadNextClientSequence)",
            "upload_queue_depth=\(uploadQueueDepth)",
            "upload_queue_high_water=\(uploadQueueHighWater)",
            "upload_sent_audio_chunks=\(uploadSentAudioChunks)",
            "upload_sent_control_commands=\(uploadSentControlCommands)",
            "upload_dropped_stale_generation_chunks=\(uploadDroppedStaleGenerationChunks)",
            "upload_rejected_after_close_commands=\(uploadRejectedAfterCloseCommands)",
            "upload_stale_generation_send_failure_count=\(uploadStaleGenerationSendFailureCount)",
            "upload_active_generation_send_failure_count=\(uploadActiveGenerationSendFailureCount)",
            "upload_input_backpressure_count=\(uploadInputBackpressureCount)",
            "upload_max_active_drain_tasks=\(uploadMaxActiveDrainTasks)",
            "upload_last_five_sent_chunk_indices=\(uploadLastFiveSentChunkIndices.map(String.init).joined(separator: ","))",
            "upload_last_send_failure_category=\(safe(uploadLastSendFailureCategory, fallback: "none"))",
            "upload_capture_to_processing_lag_ms=\(uploadCaptureToProcessingLagMilliseconds)",
            "upload_max_capture_to_processing_lag_ms=\(uploadMaxCaptureToProcessingLagMilliseconds)",
            "upload_last_capture_packet_ms=\(uploadLastCapturePacketMilliseconds)",
            "upload_max_capture_packet_ms=\(uploadMaxCapturePacketMilliseconds)",
            "upload_outbound_batch_bytes=\(uploadOutboundBatchBytes)",
            "upload_outbound_queue_depth=\(uploadOutboundQueueDepth)",
            "upload_outbound_queue_high_water=\(uploadOutboundQueueHighWater)",
            "upload_outbound_backpressure_count=\(uploadOutboundBackpressureCount)",
            "upload_outbound_oldest_queued_age_ms=\(uploadOutboundOldestQueuedAgeMilliseconds)",
            "upload_last_transport_send_ms=\(uploadLastTransportSendMilliseconds)",
            "upload_max_transport_send_ms=\(uploadMaxTransportSendMilliseconds)",
            "upload_capture_to_processing_lag_at_commit_ms=\(uploadCaptureToProcessingLagAtCommitMilliseconds)",
            "upload_commit_queued_at=\(date(uploadCommitQueuedAt, formatter: formatter))",
            "upload_commit_sent_at=\(date(uploadCommitSentAt, formatter: formatter))",
            "upload_commit_queue_to_send_ms=\(uploadCommitQueueToSendMilliseconds)",
            "upload_generation_started_at=\(date(uploadGenerationStartedAt, formatter: formatter))",
            "recovery_last_disconnect_at=\(date(recoveryLastDisconnectAt, formatter: formatter))",
            "recovery_last_reconnect_started_at=\(date(recoveryLastReconnectStartedAt, formatter: formatter))",
            "recovery_last_transport_connected_at=\(date(recoveryLastTransportConnectedAt, formatter: formatter))",
            "recovery_last_session_ready_at=\(date(recoveryLastSessionReadyAt, formatter: formatter))",
            "recovery_last_capture_resumed_at=\(date(recoveryLastCaptureResumedAt, formatter: formatter))",
            "recovery_last_gap_ms=\(optional(recoveryLastGapMilliseconds))",
            "recovery_timeline=\(recoveryTimelineText(formatter: formatter))",
            "playback_active=\(playbackActive)",
            "last_speech_duration_ms=\(lastSpeechDurationMilliseconds)",
            "last_ending_silence_ms=\(lastEndingSilenceMilliseconds)",
            "presentation_to_audio_session_ms=\(optional(presentationToAudioSessionMilliseconds))",
            "presentation_to_websocket_ms=\(optional(presentationToWebSocketMilliseconds))",
            "presentation_to_session_ready_ms=\(optional(presentationToSessionReadyMilliseconds))",
            "presentation_to_microphone_ready_ms=\(optional(presentationToMicrophoneReadyMilliseconds))",
            "response_completion_count=\(responseCompletionCount)",
            "post_response_capture_recovery_count=\(postResponseCaptureRecoveryCount)",
            "last_response_completion_capture_callbacks=\(lastResponseCompletionCaptureCallbacks)",
            "post_response_capture_callback_delta=\(postResponseCaptureCallbackDelta)",
            "generated_at=\(formatter.string(from: generatedAt))"
        ].joined(separator: "\n")
    }

    static func shortHash(_ value: String) -> String {
        guard !value.isEmpty else { return "none" }
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private func optional(_ value: Int?) -> String {
        value.map(String.init) ?? "none"
    }

    private func aggregate(
        _ samples: [VoiceLatencySample],
        _ keyPath: KeyPath<VoiceLatencySample, Int?>
    ) -> String {
        let median = aggregateValue(samples[...], keyPath, percentile: 0.50)
        let p95 = aggregateValue(samples[...], keyPath, percentile: 0.95)
        return "\(median) / \(p95)"
    }

    private func aggregate(
        _ samples: [VoiceLatencySample],
        _ keyPath: KeyPath<VoiceLatencySample, Int>
    ) -> String {
        let values = samples.map { Optional($0[keyPath: keyPath]) }
        let median = percentile(values.compactMap { $0 }, 0.50)
        let p95 = percentile(values.compactMap { $0 }, 0.95)
        return "\(optional(median)) / \(optional(p95))"
    }

    private func aggregateValue(
        _ samples: ArraySlice<VoiceLatencySample>,
        _ keyPath: KeyPath<VoiceLatencySample, Int?>,
        percentile requestedPercentile: Double
    ) -> String {
        optional(percentile(samples.compactMap { $0[keyPath: keyPath] }, requestedPercentile))
    }

    private func percentile(_ values: [Int], _ requestedPercentile: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let ordered = values.sorted()
        let rawIndex = Int((Double(ordered.count - 1) * requestedPercentile).rounded())
        return ordered[max(0, min(ordered.count - 1, rawIndex))]
    }

    private func date(_ value: Date?, formatter: ISO8601DateFormatter) -> String {
        value.map(formatter.string(from:)) ?? "none"
    }

    private func captureCallbackAgeMilliseconds() -> String {
        guard let lastCaptureCallbackAt else { return "none" }
        return String(max(0, Int(generatedAt.timeIntervalSince(lastCaptureCallbackAt) * 1000)))
    }

    private func safe(_ value: String, fallback: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(160))
    }

    private func recoveryTimelineText(formatter: ISO8601DateFormatter) -> String {
        guard !recoveryTimeline.isEmpty else { return "none" }
        return recoveryTimeline.map {
            "\(safe($0.name, fallback: "event"))@\(formatter.string(from: $0.at))"
        }.joined(separator: ",")
    }
}
