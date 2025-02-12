from ultralytics import YOLO
import cv2
import math
import pygame
from gtts import gTTS
import io
import time
import threading

# Initialize pygame mixer
pygame.mixer.init()

# Camera configuration
USE_PHONE_CAMERA = False
STREAM_URL = "http://192.168.1.106:4747/video?h=1080&w=1920&q=100"

# Video capture setup
cap = cv2.VideoCapture(STREAM_URL if USE_PHONE_CAMERA else 0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

# YOLO model
model = YOLO("yolo-Weights/yolov8n.pt")

def speak(text):
    def play_audio():
        tts = gTTS(text, lang="th")
        fp = io.BytesIO()
        tts.write_to_fp(fp)
        fp.seek(0)
        pygame.mixer.music.load(fp)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            pygame.time.Clock().tick(10)
    threading.Thread(target=play_audio).start()

# Control parameters
frame_skip = 5
last_instruction_time = 0
instruction_cooldown = 3
current_state = None
last_detection_time = 0

# Detection thresholds
confidence_threshold = 0.4
target_width_ratio = 0.68
target_height_ratio = 0.8

class AlignmentSystem:
    def __init__(self, frame_width, frame_height):
        self.frame_width = frame_width
        self.frame_height = frame_height
        self.update_target_area()
        
    def update_target_area(self):
        # Main target area
        self.target_w = int(self.frame_width * target_width_ratio)
        self.target_h = int(self.frame_height * target_height_ratio)
        self.target_x = (self.frame_width - self.target_w) // 2
        self.target_y = (self.frame_height - self.target_h) // 2
        
        # Tolerance zones
        self.position_threshold_x = int(self.frame_width * 0.05)
        self.position_threshold_y = int(self.frame_height * 0.07)
        self.min_size_ratio = 0.5  # 50% of target size
        self.max_size_ratio = 1.2  # 120% of target size

    def analyze_book(self, x1, y1, x2, y2):
        # Book dimensions
        book_w = x2 - x1
        book_h = y2 - y1
        book_area = book_w * book_h
        
        # Position analysis
        center_x = (x1 + x2) // 2
        center_y = (y1 + y2) // 2
        offset_x = center_x - self.frame_width//2
        offset_y = center_y - self.frame_height//2
        
        # Size analysis
        size_ratio = book_area / (self.target_w * self.target_h)
        
        return {
            'offset_x': offset_x,
            'offset_y': offset_y,
            'size_ratio': size_ratio,
            'width': book_w,
            'height': book_h
        }

def draw_interface(img, system):
    # Target area
    cv2.rectangle(img, 
        (system.target_x, system.target_y),
        (system.target_x + system.target_w, system.target_y + system.target_h),
        (0, 255, 255), 2)
    
    # Center markers
    cv2.drawMarker(img, (img.shape[1]//2, img.shape[0]//2),
                  (0, 255, 0), cv2.MARKER_CROSS, 20, 2)

# Initialize alignment system
ret, init_frame = cap.read()
frame_height, frame_width = init_frame.shape[:2]
alignment = AlignmentSystem(frame_width, frame_height)

while True:
    success, frame = cap.read()
    if not success:
        print("Camera error")
        break

    # Mirror flip for webcam
    if not USE_PHONE_CAMERA:
        frame = cv2.flip(frame, 1)

    # Detection processing
    current_time = time.time()
    book_detected = False
    detection_data = None
    
    if current_time - last_detection_time > 0.5:  # Limit detection rate
        results = model(frame, verbose=False)
        for result in results:
            for box in result.boxes:
                if int(box.cls) == 73 and box.conf > confidence_threshold:
                    last_detection_time = current_time
                    book_detected = True
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    detection_data = alignment.analyze_book(x1, y1, x2, y2)
                    cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 0, 255), 2)
                    break

    # State management
    if book_detected and detection_data:
        new_state = None
        sr = detection_data['size_ratio']
        ox = detection_data['offset_x']
        oy = detection_data['offset_y']

        # Size check first
        if sr < alignment.min_size_ratio:
            new_state = "closer"
        elif sr > alignment.max_size_ratio:
            new_state = "further"
        else:
            # Position check
            if abs(ox) > alignment.position_threshold_x:
                new_state = "right" if ox > 0 else "left"
            elif abs(oy) > alignment.position_threshold_y:
                new_state = "down" if oy > 0 else "up"
            else:
                new_state = "perfect"

        # State transition
        if new_state != current_state and (current_time - last_instruction_time) > instruction_cooldown:
            instructions = {
                "perfect": "สมบูรณ์แบบ, perfect",
                "left": "เลื่อนซ้าย, left",
                "right": "เลื่อนขวา, right",
                "up": "เลื่อนขึ้น, up",
                "down": "เลื่อนลง, down",
                "closer": "เข้าใกล้มากขึ้น, closer",
                "further": "ถอยออกไป, further"
            }
            speak(instructions[new_state])
            current_state = new_state
            last_instruction_time = current_time

    elif current_time - last_detection_time > 3:
        if (current_time - last_instruction_time) > instruction_cooldown:
            speak("ไม่เห็นหนังสือ, no book")
            last_instruction_time = current_time
            current_state = None

    # Draw interface
    draw_interface(frame, alignment)
    cv2.imshow('Book Alignment', frame)
    
    if cv2.waitKey(1) == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
pygame.mixer.quit()
