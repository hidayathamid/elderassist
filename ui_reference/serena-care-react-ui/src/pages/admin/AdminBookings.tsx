import { useState } from "react";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { BottomSheet } from "@/components/shared/BottomSheet";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { bookings } from "@/data/mockData";
import { Search, Filter, Eye, Edit, MoreVertical, Calendar, Clock, MapPin, User } from "lucide-react";

const AdminBookings = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedBooking, setSelectedBooking] = useState<typeof bookings[0] | null>(null);

  const allBookings = [
    ...bookings,
    {
      id: "bk4",
      caregiver: bookings[0].caregiver,
      familyMember: bookings[1].familyMember,
      date: "2024-12-18",
      time: "11:00 AM",
      status: "pending",
      service: "Medical Care",
      price: "RM 100",
      notes: "",
    },
    {
      id: "bk5",
      caregiver: bookings[1].caregiver,
      familyMember: bookings[0].familyMember,
      date: "2024-12-08",
      time: "03:00 PM",
      status: "cancelled",
      service: "Physical Therapy",
      price: "RM 120",
      notes: "Cancelled by user",
    },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Bookings</h1>
          <p className="text-muted-foreground">Manage all booking requests and appointments</p>
        </div>
        <Button>Create Booking</Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-5 gap-4">
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-foreground">3,420</p>
          <p className="text-sm text-muted-foreground">Total</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-primary">45</p>
          <p className="text-sm text-muted-foreground">Scheduled</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-warning">28</p>
          <p className="text-sm text-muted-foreground">Pending</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-success">3,320</p>
          <p className="text-sm text-muted-foreground">Completed</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-emergency">27</p>
          <p className="text-sm text-muted-foreground">Cancelled</p>
        </Card>
      </div>

      {/* Search and Filters */}
      <Card variant="default" padding="sm">
        <div className="flex items-center gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search by booking ID, user, or caregiver..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
            />
          </div>
          <Button variant="outline">
            <Filter className="h-4 w-4 mr-2" />
            Filters
          </Button>
        </div>
      </Card>

      {/* Bookings Table */}
      <Card variant="default" padding="none">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID</TableHead>
              <TableHead>User / Person</TableHead>
              <TableHead>Caregiver</TableHead>
              <TableHead>Date & Time</TableHead>
              <TableHead>Service</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Price</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {allBookings.map((booking) => (
              <TableRow key={booking.id}>
                <TableCell>
                  <span className="font-mono text-sm">{booking.id.toUpperCase()}</span>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <Avatar src={booking.familyMember.photo} name={booking.familyMember.name} size="sm" />
                    <div>
                      <p className="font-medium text-foreground">{booking.familyMember.name}</p>
                      <p className="text-xs text-muted-foreground truncate max-w-[150px]">{booking.familyMember.address}</p>
                    </div>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <Avatar src={booking.caregiver.photo} name={booking.caregiver.name} size="sm" />
                    <span className="text-sm">{booking.caregiver.name}</span>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex flex-col">
                    <span className="text-sm font-medium">{booking.date}</span>
                    <span className="text-xs text-muted-foreground">{booking.time}</span>
                  </div>
                </TableCell>
                <TableCell>
                  <Badge variant="secondary">{booking.service}</Badge>
                </TableCell>
                <TableCell>
                  <StatusBadge status={booking.status as any} />
                </TableCell>
                <TableCell>
                  <span className="font-medium">{booking.price}</span>
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex items-center justify-end gap-2">
                    <Button variant="ghost" size="iconSm" onClick={() => setSelectedBooking(booking)}>
                      <Eye className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="iconSm">
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="iconSm">
                      <MoreVertical className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>

      {/* Booking Details Sheet */}
      <BottomSheet
        open={!!selectedBooking}
        onClose={() => setSelectedBooking(null)}
        title={`Booking ${selectedBooking?.id.toUpperCase()}`}
        height="full"
      >
        {selectedBooking && (
          <div className="space-y-6">
            {/* Status */}
            <Card variant={selectedBooking.status === "completed" ? "success" : selectedBooking.status === "cancelled" ? "emergency" : "default"} padding="sm">
              <div className="flex items-center justify-between">
                <span className="font-medium">Status</span>
                <StatusBadge status={selectedBooking.status as any} />
              </div>
            </Card>

            {/* Timeline */}
            <Card variant="outline" padding="sm">
              <h4 className="font-semibold text-foreground mb-3">Timeline</h4>
              <div className="space-y-3">
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 bg-success rounded-full" />
                  <span className="text-sm">Booking created</span>
                  <span className="text-xs text-muted-foreground ml-auto">Dec 10, 10:30 AM</span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 bg-success rounded-full" />
                  <span className="text-sm">Caregiver assigned</span>
                  <span className="text-xs text-muted-foreground ml-auto">Dec 10, 10:32 AM</span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 bg-primary rounded-full" />
                  <span className="text-sm">Awaiting session</span>
                  <span className="text-xs text-muted-foreground ml-auto">Scheduled</span>
                </div>
              </div>
            </Card>

            {/* Person Details */}
            <Card variant="outline" padding="sm">
              <h4 className="font-semibold text-foreground mb-3">Person Details</h4>
              <div className="flex items-center gap-3 mb-3">
                <Avatar src={selectedBooking.familyMember.photo} name={selectedBooking.familyMember.name} size="md" />
                <div>
                  <p className="font-medium text-foreground">{selectedBooking.familyMember.name}</p>
                  <p className="text-sm text-muted-foreground">{selectedBooking.familyMember.age} years old</p>
                </div>
              </div>
              <div className="flex items-start gap-2 text-sm text-muted-foreground">
                <MapPin className="h-4 w-4 mt-0.5" />
                <span>{selectedBooking.familyMember.address}</span>
              </div>
            </Card>

            {/* Caregiver */}
            <Card variant="outline" padding="sm">
              <h4 className="font-semibold text-foreground mb-3">Assigned Caregiver</h4>
              <div className="flex items-center gap-3">
                <Avatar src={selectedBooking.caregiver.photo} name={selectedBooking.caregiver.name} size="md" />
                <div className="flex-1">
                  <p className="font-medium text-foreground">{selectedBooking.caregiver.name}</p>
                  <p className="text-sm text-muted-foreground">{selectedBooking.caregiver.specialization}</p>
                </div>
                <Button variant="outline" size="sm">Change</Button>
              </div>
            </Card>

            {/* Notes */}
            {selectedBooking.notes && (
              <Card variant="outline" padding="sm">
                <h4 className="font-semibold text-foreground mb-2">Notes</h4>
                <p className="text-sm text-muted-foreground">{selectedBooking.notes}</p>
              </Card>
            )}

            {/* Actions */}
            <div className="flex gap-3">
              <Button variant="outline" className="flex-1">Reassign Caregiver</Button>
              <Button variant="emergency" className="flex-1">Cancel Booking</Button>
            </div>
          </div>
        )}
      </BottomSheet>
    </div>
  );
};

export default AdminBookings;
