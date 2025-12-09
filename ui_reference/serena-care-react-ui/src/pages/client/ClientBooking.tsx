import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { ClientNav } from "@/components/shared/MobileNav";
import { CaregiverCard } from "@/components/shared/CaregiverCard";
import { BottomSheet } from "@/components/shared/BottomSheet";
import { Avatar } from "@/components/shared/Avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { caregivers, familyMembers } from "@/data/mockData";
import { MapPin, Calendar, Clock, ChevronRight, Star, Check, CreditCard } from "lucide-react";

type BookingStep = "person" | "caregiver" | "datetime" | "summary";

const ClientBooking = () => {
  const navigate = useNavigate();
  const [step, setStep] = useState<BookingStep>("person");
  const [selectedPerson, setSelectedPerson] = useState(familyMembers[0]);
  const [selectedCaregiver, setSelectedCaregiver] = useState(caregivers[0]);
  const [selectedDate, setSelectedDate] = useState("Dec 15, 2024");
  const [selectedTime, setSelectedTime] = useState("09:00 AM");
  const [showPersonSheet, setShowPersonSheet] = useState(false);
  const [showDateSheet, setShowDateSheet] = useState(false);

  const handleSOS = () => navigate("/client/sos");

  const renderPersonStep = () => (
    <div className="flex-1 flex flex-col">
      {/* Map placeholder */}
      <div className="h-[40vh] bg-muted relative">
        <div className="absolute inset-0 bg-gradient-to-b from-primary/5 to-primary/20 flex items-center justify-center">
          <div className="text-center">
            <MapPin className="h-12 w-12 text-primary mx-auto mb-2" />
            <p className="text-muted-foreground">Map View</p>
          </div>
        </div>
        {/* Search bar overlay */}
        <div className="absolute top-4 left-4 right-4">
          <Card variant="elevated" padding="sm" className="flex items-center gap-3">
            <MapPin className="h-5 w-5 text-emergency" />
            <div className="flex-1">
              <p className="text-sm text-muted-foreground">Pick up at?</p>
              <p className="font-medium text-foreground truncate">{selectedPerson.address}</p>
            </div>
          </Card>
        </div>
      </div>

      {/* Person selection */}
      <Card variant="elevated" padding="none" className="flex-1 -mt-6 rounded-t-3xl">
        <div className="p-6">
          <h3 className="text-lg font-bold text-foreground mb-4">Selected Person</h3>
          <Card
            variant="action"
            padding="sm"
            className="flex items-center gap-4"
            onClick={() => setShowPersonSheet(true)}
          >
            <Avatar src={selectedPerson.photo} name={selectedPerson.name} size="lg" />
            <div className="flex-1">
              <h4 className="font-semibold text-foreground">{selectedPerson.name}</h4>
              <p className="text-sm text-muted-foreground">{selectedPerson.age} years old</p>
              <div className="flex flex-wrap gap-1 mt-1">
                {selectedPerson.conditions.map((condition) => (
                  <Badge key={condition} variant="secondary" className="text-[10px]">
                    {condition}
                  </Badge>
                ))}
              </div>
            </div>
            <ChevronRight className="h-5 w-5 text-muted-foreground" />
          </Card>

          <Button size="full" className="mt-6" onClick={() => setStep("caregiver")}>
            Choose this person
          </Button>
        </div>
      </Card>

      {/* Person selection sheet */}
      <BottomSheet
        open={showPersonSheet}
        onClose={() => setShowPersonSheet(false)}
        title="Select Person"
        height="half"
      >
        <div className="space-y-3">
          {familyMembers.map((person) => (
            <Card
              key={person.id}
              variant={selectedPerson.id === person.id ? "action" : "outline"}
              padding="sm"
              className={`flex items-center gap-4 cursor-pointer ${
                selectedPerson.id === person.id ? "border-primary" : ""
              }`}
              onClick={() => {
                setSelectedPerson(person);
                setShowPersonSheet(false);
              }}
            >
              <Avatar src={person.photo} name={person.name} size="md" />
              <div className="flex-1">
                <h4 className="font-semibold text-foreground">{person.name}</h4>
                <p className="text-sm text-muted-foreground">{person.address}</p>
              </div>
              {selectedPerson.id === person.id && (
                <Check className="h-5 w-5 text-primary" />
              )}
            </Card>
          ))}
        </div>
      </BottomSheet>
    </div>
  );

  const renderCaregiverStep = () => (
    <div className="flex-1 flex flex-col">
      {/* Map placeholder */}
      <div className="h-[35vh] bg-muted relative">
        <div className="absolute inset-0 bg-gradient-to-b from-primary/5 to-primary/20 flex items-center justify-center">
          <MapPin className="h-12 w-12 text-primary" />
        </div>
      </div>

      {/* Caregiver selection */}
      <Card variant="elevated" padding="none" className="flex-1 -mt-6 rounded-t-3xl">
        <div className="p-4">
          <Tabs defaultValue="foryou" className="w-full">
            <TabsList className="grid w-full grid-cols-4 mb-4">
              <TabsTrigger value="foryou">For You</TabsTrigger>
              <TabsTrigger value="standard">Standard</TabsTrigger>
              <TabsTrigger value="premium">Premium</TabsTrigger>
              <TabsTrigger value="all">All</TabsTrigger>
            </TabsList>

            <TabsContent value="foryou" className="space-y-3 max-h-[40vh] overflow-y-auto">
              {caregivers.filter(c => c.available).map((caregiver) => (
                <CaregiverCard
                  key={caregiver.id}
                  {...caregiver}
                  variant="detailed"
                  isMatch={true}
                  onBook={() => {
                    setSelectedCaregiver(caregiver);
                    setStep("datetime");
                  }}
                />
              ))}
            </TabsContent>

            <TabsContent value="standard" className="space-y-3">
              {caregivers.slice(0, 2).map((caregiver) => (
                <CaregiverCard
                  key={caregiver.id}
                  {...caregiver}
                  variant="detailed"
                  onBook={() => {
                    setSelectedCaregiver(caregiver);
                    setStep("datetime");
                  }}
                />
              ))}
            </TabsContent>

            <TabsContent value="premium" className="space-y-3">
              {caregivers.slice(2, 4).map((caregiver) => (
                <CaregiverCard
                  key={caregiver.id}
                  {...caregiver}
                  variant="detailed"
                  onBook={() => {
                    setSelectedCaregiver(caregiver);
                    setStep("datetime");
                  }}
                />
              ))}
            </TabsContent>
          </Tabs>

          {/* Schedule button */}
          <Button
            variant="outline"
            size="full"
            className="mt-4"
            onClick={() => setShowDateSheet(true)}
          >
            <Calendar className="h-5 w-5 mr-2" />
            Schedule for later
          </Button>
        </div>
      </Card>

      {/* Date picker sheet */}
      <BottomSheet
        open={showDateSheet}
        onClose={() => setShowDateSheet(false)}
        title="Select Date & Time"
        height="half"
      >
        <div className="space-y-6">
          <div>
            <label className="text-sm font-medium text-foreground mb-2 block">Date</label>
            <div className="grid grid-cols-3 gap-2">
              {["Dec 15", "Dec 16", "Dec 17", "Dec 18", "Dec 19", "Dec 20"].map((date) => (
                <Button
                  key={date}
                  variant={selectedDate.includes(date) ? "default" : "outline"}
                  size="sm"
                  onClick={() => setSelectedDate(`${date}, 2024`)}
                >
                  {date}
                </Button>
              ))}
            </div>
          </div>
          <div>
            <label className="text-sm font-medium text-foreground mb-2 block">Time</label>
            <div className="grid grid-cols-3 gap-2">
              {["08:00 AM", "09:00 AM", "10:00 AM", "02:00 PM", "03:00 PM", "04:00 PM"].map((time) => (
                <Button
                  key={time}
                  variant={selectedTime === time ? "default" : "outline"}
                  size="sm"
                  onClick={() => setSelectedTime(time)}
                >
                  {time}
                </Button>
              ))}
            </div>
          </div>
          <Button size="full" onClick={() => {
            setShowDateSheet(false);
            setStep("summary");
          }}>
            Book in advance
          </Button>
        </div>
      </BottomSheet>
    </div>
  );

  const renderSummaryStep = () => (
    <div className="flex-1 overflow-y-auto pb-32">
      <div className="p-4 space-y-4">
        {/* Person Card */}
        <Card variant="default" padding="sm">
          <h4 className="text-sm font-semibold text-muted-foreground mb-3">PERSON RECEIVING CARE</h4>
          <div className="flex items-center gap-3">
            <Avatar src={selectedPerson.photo} name={selectedPerson.name} size="md" />
            <div>
              <p className="font-semibold text-foreground">{selectedPerson.name}</p>
              <p className="text-sm text-muted-foreground">{selectedPerson.address}</p>
            </div>
          </div>
        </Card>

        {/* Caregiver Card */}
        <Card variant="default" padding="sm">
          <h4 className="text-sm font-semibold text-muted-foreground mb-3">CAREGIVER</h4>
          <div className="flex items-center gap-3">
            <Avatar src={selectedCaregiver.photo} name={selectedCaregiver.name} size="lg" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">{selectedCaregiver.name}</p>
              <p className="text-sm text-muted-foreground">{selectedCaregiver.specialization}</p>
              <div className="flex items-center gap-2 mt-1">
                <Star className="h-4 w-4 text-warning fill-warning" />
                <span className="text-sm font-medium">{selectedCaregiver.rating}</span>
                <span className="text-muted-foreground">•</span>
                <span className="text-sm text-muted-foreground">{selectedCaregiver.completedJobs} jobs</span>
              </div>
            </div>
          </div>
        </Card>

        {/* Date & Time */}
        <Card variant="default" padding="sm">
          <h4 className="text-sm font-semibold text-muted-foreground mb-3">DATE & TIME</h4>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <Calendar className="h-5 w-5 text-primary" />
              <span className="font-medium">{selectedDate}</span>
            </div>
            <div className="flex items-center gap-2">
              <Clock className="h-5 w-5 text-primary" />
              <span className="font-medium">{selectedTime}</span>
            </div>
          </div>
        </Card>

        {/* Reviews Preview */}
        <Card variant="default" padding="sm">
          <h4 className="text-sm font-semibold text-muted-foreground mb-3">REVIEWS</h4>
          <div className="space-y-3">
            <div className="flex items-start gap-3">
              <Avatar name="John D." size="sm" />
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-medium text-sm">John D.</span>
                  <div className="flex">
                    {[1,2,3,4,5].map(i => (
                      <Star key={i} className="h-3 w-3 text-warning fill-warning" />
                    ))}
                  </div>
                </div>
                <p className="text-sm text-muted-foreground mt-1">
                  Excellent caregiver! Very professional and caring.
                </p>
              </div>
            </div>
          </div>
        </Card>

        {/* Payment Method */}
        <Card variant="default" padding="sm">
          <h4 className="text-sm font-semibold text-muted-foreground mb-3">PAYMENT METHOD</h4>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
              <CreditCard className="h-5 w-5 text-primary" />
            </div>
            <div className="flex-1">
              <p className="font-medium">ToyyibPay FPX</p>
              <p className="text-sm text-muted-foreground">Online Banking</p>
            </div>
            <ChevronRight className="h-5 w-5 text-muted-foreground" />
          </div>
        </Card>
      </div>

      {/* Sticky bottom */}
      <div className="fixed bottom-20 left-0 right-0 bg-card border-t border-border p-4">
        <div className="flex items-center justify-between mb-3">
          <span className="text-muted-foreground">Total</span>
          <span className="text-2xl font-bold text-foreground">{selectedCaregiver.price}</span>
        </div>
        <Button size="full" onClick={() => navigate("/client/activity")}>
          Place Booking
        </Button>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <Header
        title={step === "person" ? "Choose Person" : step === "caregiver" ? "Choose Caregiver" : step === "datetime" ? "Select Time" : "Booking Summary"}
        showBack
        showNotification={false}
      />

      {step === "person" && renderPersonStep()}
      {step === "caregiver" && renderCaregiverStep()}
      {step === "datetime" && renderCaregiverStep()}
      {step === "summary" && renderSummaryStep()}

      <ClientNav onSOS={handleSOS} />
    </div>
  );
};

export default ClientBooking;
