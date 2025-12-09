import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Header } from "@/components/shared/Header";
import { ClientNav } from "@/components/shared/MobileNav";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { BottomSheet } from "@/components/shared/BottomSheet";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { bookings } from "@/data/mockData";
import { Calendar, Clock, MapPin, MessageCircle, Edit, Star, Navigation } from "lucide-react";

const ClientActivity = () => {
  const navigate = useNavigate();
  const [showEditSheet, setShowEditSheet] = useState(false);
  const [selectedBooking, setSelectedBooking] = useState(bookings[0]);

  const handleSOS = () => navigate("/client/sos");

  const upcomingBookings = bookings.filter(b => b.status === "scheduled");
  const historyBookings = bookings.filter(b => b.status === "completed" || b.status === "cancelled");

  const renderBookingCard = (booking: typeof bookings[0], isUpcoming: boolean) => {
    const isToday = booking.date === "2024-12-15"; // Simulated

    return (
      <Card key={booking.id} variant="default" padding="sm" className="mb-4">
        {/* Caregiver info */}
        <div className="flex items-start gap-3 mb-4">
          <Avatar src={booking.caregiver.photo} name={booking.caregiver.name} size="lg" />
          <div className="flex-1">
            <div className="flex items-center justify-between">
              <h4 className="font-semibold text-foreground">{booking.caregiver.name}</h4>
              <StatusBadge status={booking.status as any} />
            </div>
            <p className="text-sm text-muted-foreground">{booking.caregiver.specialization}</p>
            <div className="flex items-center gap-3 mt-2 text-sm text-muted-foreground">
              <div className="flex items-center gap-1">
                <Calendar className="h-4 w-4" />
                <span>{booking.date}</span>
              </div>
              <div className="flex items-center gap-1">
                <Clock className="h-4 w-4" />
                <span>{booking.time}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Person being cared for */}
        <Card variant="ghost" padding="none" className="bg-muted/50 p-3 rounded-lg mb-4">
          <div className="flex items-center gap-2">
            <Avatar src={booking.familyMember.photo} name={booking.familyMember.name} size="sm" />
            <div>
              <p className="text-sm font-medium text-foreground">{booking.familyMember.name}</p>
              <p className="text-xs text-muted-foreground">{booking.familyMember.address}</p>
            </div>
          </div>
        </Card>

        {/* Actions */}
        {isUpcoming && (
          <div className="flex gap-2">
            {isToday ? (
              <>
                <Button variant="default" className="flex-1" onClick={() => navigate("/client/tracking")}>
                  <Navigation className="h-4 w-4 mr-1" />
                  Track
                </Button>
                <Button variant="outline" className="flex-1">
                  <MessageCircle className="h-4 w-4 mr-1" />
                  Chat
                </Button>
              </>
            ) : (
              <>
                <Button variant="outline" className="flex-1" onClick={() => navigate("/client/booking-details")}>
                  View Details
                </Button>
                <Button variant="outline" className="flex-1" onClick={() => {
                  setSelectedBooking(booking);
                  setShowEditSheet(true);
                }}>
                  <Edit className="h-4 w-4 mr-1" />
                  Edit
                </Button>
                <Button variant="outline" size="icon">
                  <MessageCircle className="h-4 w-4" />
                </Button>
              </>
            )}
          </div>
        )}

        {!isUpcoming && booking.status === "completed" && (
          <div className="flex gap-2">
            <Button variant="cardAction" className="flex-1">
              Book Again
            </Button>
            <Button variant="outline" className="flex-1">
              <Star className="h-4 w-4 mr-1" />
              Review
            </Button>
          </div>
        )}
      </Card>
    );
  };

  return (
    <div className="min-h-screen bg-background pb-24">
      <Header title="Activity" showNotification notificationCount={2} />

      <main className="px-4 py-4">
        <Tabs defaultValue="upcoming" className="w-full">
          <TabsList className="grid w-full grid-cols-2 mb-6">
            <TabsTrigger value="upcoming">Upcoming</TabsTrigger>
            <TabsTrigger value="history">History</TabsTrigger>
          </TabsList>

          <TabsContent value="upcoming">
            {upcomingBookings.length > 0 ? (
              upcomingBookings.map((booking) => renderBookingCard(booking, true))
            ) : (
              <Card variant="ghost" className="text-center py-12">
                <Calendar className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
                <h3 className="font-semibold text-foreground mb-2">No upcoming bookings</h3>
                <p className="text-muted-foreground mb-4">Book a caregiver to get started</p>
                <Button onClick={() => navigate("/client/book")}>Book Now</Button>
              </Card>
            )}
          </TabsContent>

          <TabsContent value="history">
            {historyBookings.length > 0 ? (
              historyBookings.map((booking) => renderBookingCard(booking, false))
            ) : (
              <Card variant="ghost" className="text-center py-12">
                <Clock className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
                <h3 className="font-semibold text-foreground mb-2">No booking history</h3>
                <p className="text-muted-foreground">Your completed bookings will appear here</p>
              </Card>
            )}
          </TabsContent>
        </Tabs>
      </main>

      {/* Edit Booking Sheet */}
      <BottomSheet
        open={showEditSheet}
        onClose={() => setShowEditSheet(false)}
        title="Edit Booking"
        height="half"
      >
        <div className="space-y-3">
          <Button variant="outline" size="full" className="justify-start">
            <Avatar src={selectedBooking.familyMember.photo} name={selectedBooking.familyMember.name} size="sm" className="mr-3" />
            Change Person
          </Button>
          <Button variant="outline" size="full" className="justify-start">
            <Calendar className="h-5 w-5 mr-3 text-primary" />
            Change Date & Time
          </Button>
          <Button variant="outline" size="full" className="justify-start">
            <Avatar src={selectedBooking.caregiver.photo} name={selectedBooking.caregiver.name} size="sm" className="mr-3" />
            Change Caregiver
          </Button>
          <Button variant="outline" size="full" className="justify-start">
            <Edit className="h-5 w-5 mr-3 text-primary" />
            Edit Notes
          </Button>
          <div className="pt-4 border-t border-border">
            <Button variant="emergency" size="full">
              Cancel Booking
            </Button>
          </div>
        </div>
      </BottomSheet>

      <ClientNav onSOS={handleSOS} />
    </div>
  );
};

export default ClientActivity;
