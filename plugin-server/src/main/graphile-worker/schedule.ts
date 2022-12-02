import Piscina from '@posthog/piscina'
import { JobHelpers } from 'graphile-worker'

import { KAFKA_SCHEDULED_TASKS } from '../../config/kafka-topics'
import { Hub, PluginConfigId } from '../../types'
import { status } from '../../utils/status'
import { delay } from '../../utils/utils'

type TaskTypes = 'runEveryMinute' | 'runEveryHour' | 'runEveryDay'

export async function loadPluginSchedule(piscina: Piscina, maxIterations = 2000): Promise<Hub['pluginSchedule']> {
    let allThreadsReady = false
    while (maxIterations--) {
        // Make sure the schedule loaded successfully on all threads
        if (!allThreadsReady) {
            const threadsScheduleReady = await piscina.broadcastTask({ task: 'pluginScheduleReady' })
            allThreadsReady = threadsScheduleReady.every((res) => res)
        }

        if (allThreadsReady) {
            // Having ensured the schedule is loaded on all threads, pull it from only one of them
            const schedule = (await piscina.run({ task: 'getPluginSchedule' })) as Record<
                string,
                PluginConfigId[]
            > | null
            if (schedule) {
                return schedule
            }
        }
        await delay(200)
    }
    throw new Error('Could not load plugin schedule in time')
}

export async function runScheduledTasks(server: Hub, taskType: TaskTypes, helpers: JobHelpers): Promise<void> {
    // If the tasks run_at is older than the grace period, we ignore it. We
    // don't want to end up with old tasks being scheduled if we are backed up.
    if (new Date(helpers.job.run_at).getTime() < Date.now() - gracePeriodMilliSecondsByTaskType[taskType]) {
        status.warn('🔁', 'stale_scheduled_task_skipped', {
            taskType: taskType,
            runAt: helpers.job.run_at,
        })
        server.statsd?.increment('skipped_scheduled_tasks', { taskType })
        return
    }

    for (const pluginConfigId of server.pluginSchedule?.[taskType] || []) {
        status.info('⏲️', 'queueing_schedule_task', { taskType, pluginConfigId })
        await server.kafkaProducer.producer.send({
            topic: KAFKA_SCHEDULED_TASKS,
            messages: [{ key: pluginConfigId.toString(), value: JSON.stringify({ taskType, pluginConfigId }) }],
        })
        server.statsd?.increment('queued_scheduled_task', { taskType })
    }
}

const gracePeriodMilliSecondsByTaskType = {
    runEveryMinute: 60 * 1000,
    runEveryHour: 60 * 60 * 1000,
    runEveryDay: 24 * 60 * 60 * 1000,
} as const
