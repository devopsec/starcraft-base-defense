#pragma once

#include <AzCore/Component/Component.h>
#include <AzCore/Component/TickBus.h>

#include <sbd.h>

static_assert(sizeof(sbd_vec3) == 12 && sizeof(sbd_config) == 48 && sizeof(sbd_cmd) == 24 && sizeof(sbd_event) == 28,
    "sbd.h layout must match the Zig core");

namespace SbdCore
{
    //! Creates the core world and ticks it each frame (the "sample component that ticks the world").
    //! Commands are queued from engine code with Send(); events are drained after every tick.
    class SbdCoreSystemComponent
        : public AZ::Component
        , public AZ::TickBus::Handler
    {
    public:
        AZ_COMPONENT(SbdCoreSystemComponent, "{6F2B7B1E-5B1D-4C0D-9B6B-5BD1C0DE0001}");

        static void Reflect(AZ::ReflectContext* context);
        static void GetProvidedServices(AZ::ComponentDescriptor::DependencyArrayType& provided);

        void Activate() override;
        void Deactivate() override;

        void Send(const sbd_cmd& cmd) { m_pending.push_back(cmd); }

    private:
        void OnTick(float deltaTime, AZ::ScriptTimePoint time) override;
        void HandleEvent(const sbd_event& event);

        static constexpr uint32_t ParallelThreshold = 32;
        static constexpr uint32_t ChunkSize = 16;

        sbd_world* m_world = nullptr;
        AZStd::vector<sbd_cmd> m_pending;
    };
}
