import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { CaregiverNav } from "@/components/shared/MobileNav";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { BottomSheet } from "@/components/shared/BottomSheet";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { bookings, familyMembers } from "@/data/mockData";
import { 
  MapPin, Clock, DollarSign, Phone, MessageCircle, 
  Navigation, CheckCircle, XCircle, Play, Square
} from "lucide-react";

const CaregiverJobs = () => {
  const navigate = useNavigate();
  const [showIncomingJob, setShowIncomingJob] = useState(true);
  const [activeJobStatus, setActiveJobStatus] = useState<"pending" | "on-way" | "arrived" | "started" | "completed">("pending");

  const incomingJob = {
    id: "new1",
    user: { name: "Ahmad Ibrahim", phone: "+60 12-345 6789" },
    person: familyMembers[0],
    address: "123 Jalan Merdeka, Kuala Lumpur",
    distance: "2.5 km",
    time: "Now",
    service: "Elderly Care",
    fee: "RM 80",
  };

  const activeJob = bookings[0];
  const completedJobs = bookings.filter(b => b.status === "completed");

  const handleAcceptJob = () => {
    setShowIncomingJob(false);
    setActiveJobStatus("on-way");
  };

  const handleRejectJob = () => {
    setShowIncomingJob(false);
  };

  const progressJob = () => {
    const statuses: typeof activeJobStatus[] = ["on-way", "arrived", "started", "completed"];
    const currentIndex = statuses.indexOf(activeJobStatus);
    if (currentIndex < statuses.length - 1) {
      setActiveJobStatus(statuses[currentIndex + 1]);
    }
  };

  const getActionButton = () => {
    switch (activeJobStatus) {
      case "pending":
        return { label: "Start Navigation", icon: Navigation, variant: "default" as const };
      case "on-way":
        return { label: "Mark Arrived", icon: CheckCircle, variant: "default" as const };
      case "arrived":
        return { label: "Start Session", icon: Play, variant: "success" as const };
      case "started":
        return { label: "End Session", icon: Square, variant: "emergency" as const };
      default:
        return null;
    }
  };

  const actionButton = getActionButton();

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header title="Jobs" showNotification notificationCount={1} />

      <main className="px-4 py-4">
        <Tabs defaultValue="active" className="w-full">
          <TabsList className="grid w-full grid-cols-3 mb-6">
            <TabsTrigger value="active">Active</TabsTrigger>
            <TabsTrigger value="upcoming">Upcoming</TabsTrigger>
            <TabsTrigger value="history">History</TabsTrigger>
          </TabsList>

          <TabsContent value="active">
            {activeJobStatus !== "completed" ? (
              <Card variant="default" padding="sm">
                {/* Status indicator */}
                <div className="flex items-center gap-2 mb-4">
                  <div className={`w-2 h-2 rounded-full ${
                    activeJobStatus === "started" ? "bg-success animate-pulse" : "bg-primary"
                  }`} />
                  <span className="font-medium text-foreground">
                    {activeJobStatus === "on-way" && "On the way"}
                    {activeJobStatus === "arrived" && "Arrived at location"}
                    {activeJobStatus === "started" && "Session in progress"}
                    {activeJobStatus === "pending" && "Ready to start"}
                  </span>
                </div>

                {/* Person details */}
                <div className="flex items-start gap-3 mb-4">
                  <Avatar src={activeJob.familyMember.photo} name={activeJob.familyMember.name} size="lg" />
                  <div className="flex-1">
                    <h4 className="font-semibold text-foreground">{activeJob.familyMember.name}</h4>
                    <p className="text-sm text-muted-foreground">{activeJob.familyMember.age} years old</p>
                    <div className="flex flex-wrap gap-1 mt-1">
                      {activeJob.familyMember.conditions.map((c) => (
                        <Badge key={c} variant="secondary" className="text-[10px]">{c}</Badge>
                      ))}
                    </div>
                  </div>
                </div>

                {/* Address with map preview */}
                <Card variant="ghost" className="bg-muted/50 p-3 rounded-lg mb-4">
                  <div className="flex items-center gap-2 mb-2">
                    <MapPin className="h-4 w-4 text-primary" />
                    <span className="text-sm font-medium text-foreground">{activeJob.familyMember.address}</span>
                  </div>
                  <div className="h-24 bg-primary/10 rounded-lg flex items-center justify-center">
                    <MapPin className="h-8 w-8 text-primary/50" />
                  </div>
                </Card>

                {/* Service details */}
                <div className="flex items-center justify-between py-3 border-t border-border">
                  <div className="flex items-center gap-2">
                    <Clock className="h-4 w-4 text-muted-foreground" />
                    <span className="text-sm text-muted-foreground">{activeJob.service}</span>
                  </div>
                  <span className="font-semibold text-foreground">{activeJob.price}</span>
                </div>

                {/* Notes */}
                {activeJob.notes && (
                  <div className="py-3 border-t border-border">
                    <p className="text-sm text-muted-foreground">Notes: {activeJob.notes}</p>
                  </div>
                )}

                {/* Actions */}
                <div className="flex gap-2 mt-4">
                  <Button variant="outline" size="icon">
                    <Phone className="h-5 w-5" />
                  </Button>
                  <Button variant="outline" size="icon">
                    <MessageCircle className="h-5 w-5" />
                  </Button>
                  {actionButton && (
                    <Button 
                      variant={actionButton.variant} 
                      className="flex-1"
                      onClick={progressJob}
                    >
                      <actionButton.icon className="h-5 w-5 mr-2" />
                      {actionButton.label}
                    </Button>
                  )}
                </div>
              </Card>
            ) : (
              <Card variant="success" className="text-center py-8">
                <CheckCircle className="h-12 w-12 text-success mx-auto mb-4" />
                <h3 className="font-semibold text-foreground mb-2">Session Completed!</h3>
                <p className="text-muted-foreground mb-4">Great job! You've completed the session.</p>
                <Button onClick={() => setActiveJobStatus("pending")}>View Next Job</Button>
              </Card>
            )}
          </TabsContent>

          <TabsContent value="upcoming">
            <div className="space-y-3">
              {bookings.filter(b => b.status === "scheduled").map((job) => (
                <Card key={job.id} variant="default" padding="sm">
                  <div className="flex items-start gap-3">
                    <Avatar src={job.familyMember.photo} name={job.familyMember.name} size="md" />
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <h4 className="font-semibold text-foreground">{job.familyMember.name}</h4>
                        <StatusBadge status="scheduled" />
                      </div>
                      <div className="flex items-center gap-3 mt-2 text-sm text-muted-foreground">
                        <div className="flex items-center gap-1">
                          <Clock className="h-4 w-4" />
                          <span>{job.date} • {job.time}</span>
                        </div>
                      </div>
                      <div className="flex items-center gap-1 mt-1 text-sm text-muted-foreground">
                        <MapPin className="h-4 w-4" />
                        <span className="truncate">{job.familyMember.address}</span>
                      </div>
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          </TabsContent>

          <TabsContent value="history">
            <div className="space-y-3">
              {completedJobs.map((job) => (
                <Card key={job.id} variant="default" padding="sm">
                  <div className="flex items-start gap-3">
                    <Avatar src={job.familyMember.photo} name={job.familyMember.name} size="md" />
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <h4 className="font-semibold text-foreground">{job.familyMember.name}</h4>
                        <span className="font-semibold text-success">{job.price}</span>
                      </div>
                      <p className="text-sm text-muted-foreground">{job.service}</p>
                      <p className="text-xs text-muted-foreground mt-1">{job.date}</p>
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          </TabsContent>
        </Tabs>
      </main>

      {/* Incoming Job Request Modal */}
      <BottomSheet
        open={showIncomingJob}
        onClose={() => setShowIncomingJob(false)}
        title="New Job Request"
        height="auto"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Avatar src={incomingJob.person.photo} name={incomingJob.person.name} size="lg" />
            <div>
              <h4 className="font-semibold text-foreground">{incomingJob.person.name}</h4>
              <p className="text-sm text-muted-foreground">{incomingJob.person.age} years old</p>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm">{incomingJob.distance}</span>
            </div>
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm">{incomingJob.time}</span>
            </div>
          </div>

          <Card variant="ghost" className="bg-muted/50 p-3 rounded-lg">
            <p className="text-sm text-muted-foreground">{incomingJob.address}</p>
          </Card>

          <div className="flex items-center justify-between py-2">
            <span className="text-muted-foreground">{incomingJob.service}</span>
            <span className="text-xl font-bold text-foreground">{incomingJob.fee}</span>
          </div>

          <div className="flex gap-3">
            <Button variant="outline" className="flex-1" onClick={handleRejectJob}>
              <XCircle className="h-5 w-5 mr-2" />
              Reject
            </Button>
            <Button variant="success" className="flex-1" onClick={handleAcceptJob}>
              <CheckCircle className="h-5 w-5 mr-2" />
              Accept
            </Button>
          </div>
        </div>
      </BottomSheet>

      <CaregiverNav />
    </div>
  );
};

export default CaregiverJobs;
