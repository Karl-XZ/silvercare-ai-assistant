import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

function readJsonl(file) {
  const text = fs.readFileSync(file, 'utf8').trim();
  if (!text) return [];
  return text.split(/\r?\n/).map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      throw new Error(`${file}:${index + 1} JSON parse failed: ${error.message}`);
    }
  });
}

function careEvent(eventType, summary, riskLevel = 'medium') {
  return {
    reviewable: true,
    event_type: eventType,
    risk_level: riskLevel,
    summary,
    fields: ['event_type', 'risk_level', 'sensor_summary', 'visual_summary', 'action_taken']
  };
}

const outputs = {
  nav_corridor_001: {
    latency_ms: 420,
    output: {
      category: 'navigation',
      priority: 'low',
      speech: '可以向前慢走，脚下有脚垫，脚抬高一点，保持在走廊中间。',
      subtitle: '可以向前慢走，脚下有脚垫，脚抬高一点，保持在走廊中间。',
      screen_required: false,
      voice_first_ready: true
    }
  },
  nav_luggage_entry_001: {
    latency_ms: 510,
    output: {
      category: 'navigation',
      priority: 'medium',
      speech: '左侧是行李和蓝色袋子，右侧有纸箱，通道变窄。请贴近右侧白色柱子慢慢走。',
      subtitle: '左侧是行李和蓝色袋子，右侧有纸箱，通道变窄。请贴近右侧白色柱子慢慢走。',
      screen_required: false,
      voice_first_ready: true
    }
  },
  fall_risk_rack_001: {
    latency_ms: 560,
    output: {
      category: 'hazard',
      priority: 'critical',
      speech: '先停下，前方地面有倒下的晾衣架，不要跨过去。请后退半步，等待清理或换路线。',
      subtitle: '先停下，前方地面有倒下的晾衣架，不要跨过去。请后退半步，等待清理或换路线。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('environment_hazard', '前方通道出现倒地晾衣架，建议照护人员复核并清理。', 'critical')
    }
  },
  bathroom_guidance_001: {
    latency_ms: 490,
    output: {
      category: 'bathroom_safety',
      priority: 'high',
      speech: '请先扶住门边或墙面，慢慢进入。前面有淋浴间门槛，地面可能湿滑，脚步放小。',
      subtitle: '请先扶住门边或墙面，慢慢进入。前面有淋浴间门槛，地面可能湿滑，脚步放小。',
      screen_required: false,
      voice_first_ready: true
    }
  },
  find_earplug_box_001: {
    latency_ms: 530,
    output: {
      category: 'object_search',
      priority: 'medium',
      target_detected: true,
      speech: '耳塞盒在你正前方偏右的桌面上，靠近白色圆柱设备左下方。先摸到桌面前边缘，再向右移动，注意脚边电线。',
      subtitle: '耳塞盒在你正前方偏右的桌面上，靠近白色圆柱设备左下方。先摸到桌面前边缘，再向右移动，注意脚边电线。',
      screen_required: false,
      voice_first_ready: true
    }
  },
  video_change_obstacle_001: {
    latency_ms: 690,
    output: {
      category: 'scene_change',
      priority: 'critical',
      speech: '画面变化很大，前方新出现倒地晾衣架。先停下，不要继续直走，我会重新规划路线。',
      subtitle: '画面变化很大，前方新出现倒地晾衣架。先停下，不要继续直走，我会重新规划路线。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('scene_change_hazard', '视频前后画面显示通道新增倒地障碍，需要复核。', 'critical')
    }
  },
  asr_find_door_001: {
    latency_ms: 180,
    output: {
      category: 'voice_command',
      priority: 'low',
      transcript: '找门在哪里',
      speech: '收到，开始帮你找门。',
      subtitle: '找门在哪里',
      screen_required: false,
      voice_first_ready: true
    }
  },
  asr_start_navigation_001: {
    latency_ms: 170,
    output: {
      category: 'voice_command',
      priority: 'low',
      transcript: '开始巡路',
      speech: '收到，开始巡路。',
      subtitle: '开始巡路',
      screen_required: false,
      voice_first_ready: true
    }
  },
  asr_task_water_001: {
    latency_ms: 190,
    output: {
      category: 'care_need',
      priority: 'medium',
      transcript: '我想喝水',
      speech: '已记录喝水需求。请先坐稳，我会提醒照护人员查看。',
      subtitle: '我想喝水',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('daily_need', '用户表达喝水需求，建议照护人员确认。', 'medium')
    }
  },
  fall_confirm_timeout_001: {
    latency_ms: 1040,
    output: {
      category: 'fall_confirmation',
      priority: 'critical',
      alarm_status: 'simulated_alarm',
      confirmation_prompt: '检测到可能摔倒了。你是否摔倒？十秒内说没事可以取消报警。',
      speech: '检测到可能摔倒了。你是否摔倒？十秒内未回应，将进行模拟报警。',
      subtitle: '检测到可能摔倒了。你是否摔倒？十秒内未回应，将进行模拟报警。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('fall_risk', '传感器剧烈变化且画面变化明显，用户十秒未回应，已模拟报警。', 'critical')
    }
  },
  fall_confirm_cancel_001: {
    latency_ms: 620,
    output: {
      category: 'fall_confirmation',
      priority: 'low',
      alarm_status: 'cancelled',
      speech: '收到，你说没摔倒，报警已取消。我会继续观察一小段时间。',
      subtitle: '收到，你说没摔倒，报警已取消。我会继续观察一小段时间。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('fall_alarm_cancelled', '用户确认没摔倒，系统取消报警并保留复核记录。', 'low')
    }
  },
  false_positive_sensor_only_001: {
    latency_ms: 480,
    output: {
      category: 'false_alarm',
      priority: 'low',
      alarm_status: 'no_alarm',
      speech: '检测到手机晃动，但画面没有明显摔倒变化，没有触发报警。',
      subtitle: '检测到手机晃动，但画面没有明显摔倒变化，没有触发报警。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('fall_false_positive_suppressed', '只有传感器突变，画面没有明显摔倒变化，未触发报警。', 'low')
    }
  },
  manual_correction_navigation_001: {
    latency_ms: 450,
    output: {
      category: 'manual_correction',
      priority: 'medium',
      manual_correction_applied: true,
      speech: '已按你的修正，改为贴右侧白色柱子慢走，左脚不要靠近左侧行李。',
      subtitle: '已按你的修正，改为贴右侧白色柱子慢走，左脚不要靠近左侧行李。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('manual_correction', '用户指出左侧被占用，系统改为右侧通行方案。', 'medium')
    }
  },
  care_review_event_001: {
    latency_ms: 360,
    output: {
      category: 'care_review',
      priority: 'medium',
      speech: '找物任务已完成，已生成照护复核记录，照护人员可以查看任务开始、引导、用户确认和完成结果。',
      subtitle: '找物任务已完成，已生成照护复核记录。',
      screen_required: false,
      voice_first_ready: true,
      care_event: careEvent('task_completion', '找物任务完成，照护端可复核全过程。', 'medium')
    }
  }
};

const tasks = readJsonl(path.join(root, 'dataset', 'tasks.jsonl'));
const outFile = path.join(root, 'dataset', 'baselines', 'rule_based_baseline.jsonl');

const lines = tasks.map((task) => {
  const item = outputs[task.task_id];
  if (!item) {
    throw new Error(`No baseline output for task ${task.task_id}`);
  }
  return JSON.stringify({
    task_id: task.task_id,
    baseline: 'rule_based_v0',
    latency_ms: item.latency_ms,
    output: item.output
  });
});

fs.writeFileSync(outFile, `${lines.join('\n')}\n`, 'utf8');
console.log(`Wrote ${lines.length} baseline outputs to ${path.relative(root, outFile)}`);

