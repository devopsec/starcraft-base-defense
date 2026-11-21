#include "SbdCoreSystemComponent.h"

#include <AzCore/Jobs/Algorithms.h>
#include <AzCore/Serialization/SerializeContext.h>
#include <AzCore/std/algorithm.h>

namespace SbdCore
{
    void SbdCoreSystemComponent::Reflect(AZ::ReflectContext* context)
    {
        if (auto* serialize = azrtti_cast<AZ::SerializeContext*>(context))
        {
            serialize->Class<SbdCoreSystemComponent, AZ::Component>()->Version(0);
        }
    }

    void SbdCoreSystemComponent::GetProvidedServices(AZ::ComponentDescriptor::DependencyArrayType& provided)
    {
        provided.push_back(AZ_CRC_CE("SbdCoreService"));
    }

    void SbdCoreSystemComponent::Activate()
    {
        sbd_config config;
        sbd_config_default(&config); // TODO: load data/balance.json like the other adapters
        m_world = sbd_world_create(&config);
        AZ::TickBus::Handler::BusConnect();
    }

    void SbdCoreSystemComponent::Deactivate()
    {
        AZ::TickBus::Handler::BusDisconnect();
        sbd_world_destroy(m_world);
        m_world = nullptr;
    }

    void SbdCoreSystemComponent::OnTick(float deltaTime, AZ::ScriptTimePoint)
    {
        if (!m_world)
        {
            return;
        }

        if (!m_pending.empty())
        {
            sbd_world_push(m_world, m_pending.data(), static_cast<uint32_t>(m_pending.size()));
            m_pending.clear();
        }

        // begin / step_enemies(range) / resolve is equivalent to sbd_world_tick; the ranges are
        // disjoint, so they can run on the AzCore job system once there are enough enemies.
        sbd_world_begin(m_world, deltaTime);
        const uint32_t enemies = sbd_world_enemy_count(m_world);
        if (enemies < ParallelThreshold)
        {
            sbd_world_step_enemies(m_world, 0, enemies, deltaTime);
        }
        else
        {
            sbd_world* world = m_world;
            const uint32_t chunks = (enemies + ChunkSize - 1) / ChunkSize;
            AZ::parallel_for(uint32_t(0), chunks, [world, enemies, deltaTime](uint32_t chunk)
            {
                const uint32_t begin = chunk * ChunkSize;
                sbd_world_step_enemies(world, begin, AZStd::min(begin + ChunkSize, enemies), deltaTime);
            });
        }
        sbd_world_resolve(m_world);

        sbd_event events[128];
        uint32_t count;
        while ((count = sbd_world_poll(m_world, events, 128)) > 0)
        {
            for (uint32_t i = 0; i < count; ++i)
            {
                HandleEvent(events[i]);
            }
        }
    }

    void SbdCoreSystemComponent::HandleEvent(const sbd_event& event)
    {
        // Map events to O3DE entities, animation and effects here (view layer).
        AZ_TracePrintf("SbdCore", "event kind=%u entity=%u value=%d\n", event.kind, event.entity, event.value);
    }
}
