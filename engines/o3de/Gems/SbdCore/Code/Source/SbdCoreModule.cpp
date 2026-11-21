#include <AzCore/Module/Module.h>

#include "SbdCoreSystemComponent.h"

namespace SbdCore
{
    class SbdCoreModule : public AZ::Module
    {
    public:
        AZ_RTTI(SbdCoreModule, "{6F2B7B1E-5B1D-4C0D-9B6B-5BD1C0DE0002}", AZ::Module);

        SbdCoreModule()
        {
            m_descriptors.insert(m_descriptors.end(), { SbdCoreSystemComponent::CreateDescriptor() });
        }

        AZ::ComponentTypeList GetRequiredSystemComponents() const override
        {
            return AZ::ComponentTypeList{ azrtti_typeid<SbdCoreSystemComponent>() };
        }
    };
}

AZ_DECLARE_MODULE_CLASS(Gem_SbdCore, SbdCore::SbdCoreModule)
