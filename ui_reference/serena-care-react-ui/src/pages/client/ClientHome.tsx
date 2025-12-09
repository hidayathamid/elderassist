import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { ClientNav } from "@/components/shared/MobileNav";
import { QuickActionCard } from "@/components/shared/QuickActionCard";
import { CaregiverCard } from "@/components/shared/CaregiverCard";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { caregivers } from "@/data/mockData";
import { Calendar, Search, MessageCircle, AlertTriangle, ChevronRight } from "lucide-react";

const ClientHome = () => {
  const navigate = useNavigate();
  const [showSOS, setShowSOS] = useState(false);

  const handleSOS = () => {
    navigate("/client/sos");
  };

  const previousCaregivers = caregivers.slice(0, 3);
  const nearbyCaregivers = caregivers.filter(c => c.available).slice(0, 4);
  const recommendedCaregivers = caregivers.slice(1, 5);

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header
        greeting="Good morning,"
        subtitle="Aisha Rahman"
        avatar="https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&crop=face"
        notificationCount={3}
      />

      <main className="px-4 py-6 space-y-8">
        {/* Mini Emergency Button */}
        <Button
          variant="emergency"
          onClick={handleSOS}
          className="w-full flex items-center justify-center gap-3 py-4"
        >
          <AlertTriangle className="h-5 w-5" />
          <span>Emergency SOS</span>
        </Button>

        {/* Quick Actions */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-4">Quick Actions</h2>
          <div className="grid grid-cols-3 gap-3">
            <QuickActionCard
              icon={Calendar}
              title="Book"
              subtitle="Caregiver"
              variant="primary"
              onClick={() => navigate("/client/book")}
            />
            <QuickActionCard
              icon={Search}
              title="Find"
              subtitle="Nearby"
              variant="default"
              onClick={() => navigate("/client/book")}
            />
            <QuickActionCard
              icon={MessageCircle}
              title="Chat"
              subtitle="Support"
              variant="success"
              onClick={() => {}}
            />
          </div>
        </section>

        {/* Previous Caregivers */}
        <section>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold text-foreground">Previous Caregivers</h2>
            <Button variant="ghost" size="sm" className="text-primary">
              See All <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          </div>
          <div className="flex gap-3 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-hide">
            {previousCaregivers.map((caregiver) => (
              <CaregiverCard
                key={caregiver.id}
                {...caregiver}
                onBook={() => navigate(`/client/book?caregiver=${caregiver.id}`)}
              />
            ))}
          </div>
        </section>

        {/* Nearby Caregivers */}
        <section>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold text-foreground">Nearby Caregivers</h2>
            <Button variant="ghost" size="sm" className="text-primary">
              See All <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          </div>
          <div className="flex gap-3 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-hide">
            {nearbyCaregivers.map((caregiver) => (
              <CaregiverCard
                key={caregiver.id}
                {...caregiver}
                available={true}
                onBook={() => navigate(`/client/book?caregiver=${caregiver.id}`)}
              />
            ))}
          </div>
        </section>

        {/* Recommended For You */}
        <section>
          <div className="flex items-center justify-between mb-2">
            <div>
              <h2 className="text-lg font-bold text-foreground">Recommended For You</h2>
              <p className="text-sm text-muted-foreground">Based on your service preferences</p>
            </div>
            <Button variant="ghost" size="sm" className="text-primary">
              See All <ChevronRight className="h-4 w-4 ml-1" />
            </Button>
          </div>
          <div className="flex gap-3 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-hide">
            {recommendedCaregivers.map((caregiver) => (
              <CaregiverCard
                key={caregiver.id}
                {...caregiver}
                isMatch={true}
                onBook={() => navigate(`/client/book?caregiver=${caregiver.id}`)}
              />
            ))}
          </div>
        </section>
      </main>

      <ClientNav onSOS={handleSOS} />
    </div>
  );
};

export default ClientHome;
